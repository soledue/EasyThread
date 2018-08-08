# EasyThread

![Swift 4.x](https://img.shields.io/badge/swift-4.x-EF5138.svg)
![Under MIT License](https://img.shields.io/badge/license-MIT-blue.svg)
[![Platform](https://img.shields.io/badge/Platform-iOS-lightgrey.svg)](https://developer.apple.com/)

## Requirements
- iOS 
- Xcode 

#### Serial queue
```swift
let q = EasyThread.getQueue(processors: 1)
    q.dispatch {
        print("uno")
    }
    q.dispatch {
        print("due")
    }
    q.dispatch {
        print("tre")
    }
}
```
#### Concurrent queue
````swift
let q = EasyThread.getQueue(processors: 10)
    q.dispatch {
        print("uno")
    }
    q.dispatch {
        print("due")
    }
    q.dispatch {
        print("tre")
    }
}
````
#### Promises
````swift
    try? Promise<Int>{
        return 10
    }.next { r -> String in
        let v = try 
        return "test"
    }.next { r -> Int in
        let v = try r()
        return 1
    }.fail { error in
        print(error)
    }.wait()
````


## Author

i.kanev@reply.it

## License

Short is available under the MIT license. See the LICENSE file for more info.
