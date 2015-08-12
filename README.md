# ReactiveMoya
A simpler way to use Moya+ReactiveCocoa.

Example
------------------------

ReactiveMoya is the Moya you know, with the RAC interfaces you're used to. `ReactiveMoyaProvider` immediately returns a  
`SignalProducer` or `RACSignal` that you can subscribe to or bind or map or whatever you want to
do. To handle errors, for instance, we could do the following:

```swift
provider.request(.UserProfile("ashfurrow")).subscribeNext { (object) -> Void in
    image = UIImage(data: object as? NSData)
}, error: { (error) -> Void in
    println(error)
}
```

```swift
provider.request(.UserProfile("ashfurrow"))
  |> start(error: { error in
    println(error)
  }, 
  next: { object in
    image = UIImage(data: object as? NSData)
  })
```

In addition to the option of using signals instead of callback blocks, there are
also a series of signal operators that will attempt to map the data received 
from the network response into either an image, some JSON, or a string, with 
`mapImage()`, `mapJSON()`, `mapJSONArray()`, `mapJSONDictionary()`, and `mapString()`, respectively. If the mapping is
unsuccessful, you'll get an error on the signal. You also get handy methods for
filtering out certain status codes. This means that you can place your code for 
handling API errors like 400's in the same places as code for handling invalid 
responses. 
