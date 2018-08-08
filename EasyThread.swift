//
//  Threader.swift
//
//  Created by Ivo Kanev on 07/08/2018.
//  Copyright © 2018 Reply SPA. All rights reserved.
//

import Foundation

// MARK - EasyThread
public struct EasyThread {
    private static var queques = [String: EasyThreadQueue]()
    private static let lockQueues = EasyThread.Lock()
}

public extension EasyThread {
    public class Lock {
        var mutex = pthread_mutex_t()
        public init() {
            var attr = pthread_mutexattr_t()
            pthread_mutexattr_init(&attr)
            pthread_mutexattr_settype(&attr, Int32(PTHREAD_MUTEX_RECURSIVE))
            pthread_mutex_init(&mutex, &attr)
        }
        deinit {
            pthread_mutex_destroy(&mutex)
        }
        public func lock() {
            pthread_mutex_lock(&mutex)
        }
        public func unlock() {
            pthread_mutex_unlock(&mutex)
        }
        public func doWithLock<Result>(closure: () throws -> Result) throws -> Result {
            lock()
            defer {
                unlock()
            }
            return try closure()
        }
    }
    public class Event: Lock {
        var cond = pthread_cond_t()
        override init() {
            super.init()
            var attr = pthread_condattr_t()
            pthread_condattr_init(&attr)
            pthread_cond_init(&cond, &attr)
            pthread_condattr_destroy(&attr)
        }
        deinit {
            pthread_cond_destroy(&cond)
        }
        public func signal() {
            pthread_cond_signal(&cond)
        }
        public func broadcast() {
            pthread_cond_broadcast(&cond)
        }
        @discardableResult
        public func wait(seconds: TimeInterval = 0) -> Bool{
            guard seconds > 0 else {
                return pthread_cond_wait(&cond, &mutex) == 0
            }
            var tm = timespec()
            tm.tv_sec = Int(floor(seconds))
            tm.tv_nsec = (Int(seconds * 1000.0) - (tm.tv_sec * 1000)) * 1000000
            return pthread_cond_timedwait_relative_np(&cond, &mutex, &tm) == 0
        }
    }
    public class EasyThreadQueue {
        public var name: String = "default"
        var running: Bool = true
        let lock = EasyThread.Event()
        var processors: Int
        let queue = DispatchQueue(label: "default", attributes: .concurrent)
        private var queues = [()->Void]()
        init(name: String = "default", processors: Int = 4) {
            self.name = name
            self.processors = processors
            start()
        }
        public func dispatch(_ closure: @escaping () -> Void) {
            lock.lock()
            defer {
                lock.unlock()
            }
            queues.append(closure)
            lock.signal()
        }
        private func start() {
            let new = {
                EasyThread.dispatchOnNewThread {
                    while self.running {
                        var block: (() -> Void)?
                        do {
                            self.lock.lock()
                            defer {
                                self.lock.unlock()
                            }
                            if self.queues.count > 0 {
                                block = self.queues.removeFirst()
                            } else {
                                self.lock.wait()
                                if self.queues.count > 0 {
                                    block = self.queues.removeFirst()
                                }
                            }
                        }
                        if let block = block {
                            block()
                        }
                    }
                }
            }
            for _ in 0..<processors {
                new()
            }
        }
    }
}

public extension EasyThread {
    public static func getQueue(name: String = "__undefined__", processors: Int = 4) -> EasyThreadQueue {
        EasyThread.lockQueues.lock()
        defer {
            EasyThread.lockQueues.unlock()
        }

        if let queue = EasyThread.queques.first(where: { $0.key == name } ) {
            return queue.value
        }
        let queue = EasyThreadQueue(name: name, processors: processors)
        EasyThread.queques[name] = queue
        return queue
    }
    public static func destroy(_ queue: EasyThreadQueue) {
        EasyThread.lockQueues.lock()
        defer {
            EasyThread.lockQueues.unlock()
        }
        EasyThread.queques.removeValue(forKey: queue.name)
        queue.running = false
        queue.lock.broadcast()
    }
    public static func sleep(seconds: TimeInterval) {
        guard seconds > 0.0 else {
            return
        }
        let milliseconds = Int(seconds * 1000)
        var tv = timeval()
        tv.tv_sec = milliseconds / 1000
        tv.tv_usec = Int32((milliseconds % 1000)*1000)
        select(0, nil, nil, nil, &tv)
    }
}

public extension EasyThread {
    private static func dispatchOnNewThread(closure: @escaping ()->Void) {
        let q = DispatchQueue(label: "EasyThread")
        q.async(execute: closure)
    }
}

// MARK: - Primise
struct ErrorPromise: Error {}
public class Promise<Return> {
    private let event = EasyThread.Event()
    private let queue: FastQueue
    private var value: Return?
    private var error: Error?
    public init(closure: @escaping (Promise<Return>) throws -> Void) {
        queue = FastQueue(queue: EasyThread.getQueue(processors: 1))
        queue.dispatch {
            do {
                try closure(self)
            } catch {
                self.fail(error)
            }
        }
    }
    public init(closure: @escaping () throws -> Return) {
        queue = FastQueue(queue: EasyThread.getQueue(processors: 1))
        queue.dispatch {
            do {
                self.set(try closure())
            } catch {
                self.fail(error)
            }
        }
    }
    init<Type>(from: Promise<Type>, closure: @escaping (() throws -> Type) throws -> Return) {
        queue = from.queue
        queue.dispatch {
            do {
                self.set(try closure({
                    guard let v = try from.wait() else {
                        throw ErrorPromise()
                    }
                    return v }
                    ))

            } catch {
                self.fail(error)
            }
        }
    }
}
public extension Promise {
    public func fail(closure: @escaping (Error) throws -> Void) -> Promise<Return> {
        return Promise<Return>(from: self) { value in
            do {
                return try value()
            } catch {
                try closure(error)
                throw error
            }

        }
    }
    public func next<Type>(closure: @escaping (() throws -> Return) throws -> Type) -> Promise<Type> {
        return Promise<Type>(from: self, closure: closure)
    }
    public func set(_ value: Return) {
        event.lock()
        defer {
            event.unlock()
        }
        self.value = value
        event.broadcast()
    }
    public func get() throws -> Return? {
        event.lock()
        defer {
            event.unlock()
        }
        if let error = error {
            throw error
        }
        return value
    }
    public func wait(seconds: TimeInterval = 0) throws -> Return? {
        event.lock()
        defer {
            event.unlock()
        }
        repeat {
            if let error = error {
                throw error
            }
            if let value = value {
                return value
            }
        } while event.wait(seconds: seconds)
        if let error = error {
            throw error
        }
        return value
    }
    public func fail(_ error: Error) {
        event.lock()
        defer {
            event.unlock()
        }
        self.error = error
        event.broadcast()
    }
}
class FastQueue {
    let queue: EasyThread.EasyThreadQueue
    init(queue: EasyThread.EasyThreadQueue) {
        self.queue = queue
    }
    func dispatch(_ closure: @escaping () -> Void) {
        queue.dispatch(closure)
    }
    deinit {
        EasyThread.destroy(queue)
    }
}
