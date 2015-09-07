import Foundation
import ReactiveCocoa
import Result

/// Subclass of MoyaProvider that returns SignalProducer<MoyaResponse, NSError> instances when requests are made. Much better than using completion closures.
public class ReactiveCocoaMoyaProvider<T where T: MoyaTarget>: MoyaProvider<T> {
    /// Current requests that have not completed or errored yet.
    /// Note: Do not access this directly. It is public only for unit-testing purposes (sigh).
    public var inflightRequests = Dictionary<Endpoint<T>, Signal<MoyaResponse, NSError>>()
    
    /// Initializes a reactive provider.
    override public init(endpointClosure: MoyaEndpointsClosure = MoyaProvider.DefaultEndpointMapping, endpointResolver: MoyaEndpointResolution = MoyaProvider.DefaultEnpointResolution, stubBehavior: MoyaStubbedBehavior = MoyaProvider.NoStubbingBehavior, networkActivityClosure: Moya.NetworkActivityClosure? = nil) {
        super.init(endpointClosure: endpointClosure, endpointResolver: endpointResolver, stubBehavior: stubBehavior, networkActivityClosure: networkActivityClosure)
    }
    
    public func request(token: T) -> SignalProducer<MoyaResponse, NSError> {
        let endpoint = self.endpoint(token)
        
        if let existingSignal = inflightRequests[endpoint] {
            /// returns a new producer which forwards all events of the already existing request signal
            return SignalProducer { sink, disposable in
                /// connect all events of the existing signal to the observer of this signal producer
                existingSignal.observe(sink)
            }
        }
        else {
            /// returns a new producer which starts a new producer which invokes the requests. The created signal of the inner producer is saved for inflight request
            return SignalProducer { [weak self] sink, _ in
                let producer: SignalProducer<MoyaResponse, NSError> = SignalProducer { [weak self] sink, disposable in
                    let cancellableToken = self?.request(token) { data, statusCode, response, error in
                        if let error = error {
                            if let statusCode = statusCode {
                                sendError(sink, NSError(domain: error.domain, code: statusCode, userInfo: error.userInfo))
                            } else {
                                sendError(sink, error)
                            }
                        } else {
                            if let data = data {
                                sendNext(sink, MoyaResponse(statusCode: statusCode!, data: data, response: response))
                            }
                        }
                        sendCompleted(sink)
                    }
                    
                    disposable.addDisposable {
                        if let weakSelf = self {
                            objc_sync_enter(weakSelf)
                            // Clear the inflight request
                            weakSelf.inflightRequests[endpoint] = nil
                            objc_sync_exit(weakSelf)
                            // Cancel the request
                            cancellableToken?.cancel()
                        }
                    }
                }
                
                /// starts the inner signal producer and store the created signal.
                producer |> startWithSignal { [weak self] signal, _ in
                    objc_sync_enter(self)
                    self?.inflightRequests[endpoint] = signal
                    objc_sync_exit(self)
                    /// connect all events of the signal to the observer of this signal producer
                    signal.observe(sink)
                }
            }
        }
    }
    
    public func request(token: T) -> RACSignal {
        return toRACSignal(self.request(token))
    }
}

/// Extension for mapping to a certain response type
public extension ReactiveCocoaMoyaProvider {
    public func requestJSON(token: T) -> SignalProducer<AnyObject, NSError> {
        return request(token) |> mapJSON()
    }
    
    public func requestJSONArray(token: T) -> SignalProducer<NSArray, NSError> {
        return requestJSON(token) |> mapJSONArray()
    }
    
    public func requestJSONDictionary(token: T) -> SignalProducer<NSDictionary, NSError> {
        return requestJSON(token) |> mapJSONDictionary()
    }
    
    public func requestImage(token: T) -> SignalProducer<UIImage, NSError> {
        return request(token) |> mapImage()
    }
    
    public func requestString(token: T) -> SignalProducer<String, NSError> {
        return request(token) |> mapString()
    }
}

/// MoyaResponse free functions

public func filterStatusCode(range: ClosedInterval<Int>) -> SignalProducer<MoyaResponse, NSError> -> SignalProducer<MoyaResponse, NSError>  {
    return { producer in
        return producer |> flatMap(.Latest, { response in
            if range.contains(response.statusCode) {
                return SignalProducer(value: response)
            } else {
                return SignalProducer(error: ReactiveMoyaError.StatusCode(response).toError())
            }
        })
    }
}

public func filterStatusCode(code: Int) -> SignalProducer<MoyaResponse, NSError> -> SignalProducer<MoyaResponse, NSError> {
    return filterStatusCode(code...code)
}

public func filterSuccessfulStatusCodes() -> SignalProducer<MoyaResponse, NSError> -> SignalProducer<MoyaResponse, NSError> {
    return filterStatusCode(200...299)
}

public func filterSuccessfulAndRedirectCodes() -> SignalProducer<MoyaResponse, NSError> -> SignalProducer<MoyaResponse, NSError> {
    return filterStatusCode(200...399)
}

/// Maps the `MoyaResponse` to a `UIImage`
public func mapImage() -> SignalProducer<MoyaResponse, NSError> -> SignalProducer<UIImage, NSError> {
    return { producer in
        return producer |> flatMap(.Latest, { response in
            if let image = UIImage(data: response.data) {
                return SignalProducer(value: image)
            } else {
                return SignalProducer(error: ReactiveMoyaError.ImageMapping(response).toError())
            }
        })
    }
}

/// Maps the `MoyaResponse` to JSON
public func mapJSON() -> SignalProducer<MoyaResponse, NSError> -> SignalProducer<AnyObject, NSError> {
    return { producer in
        return producer |> flatMap(.Latest, { response in
            var error: NSError?
            if let json: AnyObject = NSJSONSerialization.JSONObjectWithData(response.data, options: .AllowFragments, error: &error) {
                return SignalProducer(value: json)
            } else {
                return SignalProducer(error: ReactiveMoyaError.JSONMapping(response).toError())
            }
        })
    }
}

/// Maps a JSON object to an NSArray
public func mapJSONArray() -> SignalProducer<AnyObject, NSError> -> SignalProducer<NSArray, NSError> {
    return { producer in
        return producer |> flatMap(.Latest, { json in
            if let json = json as? NSArray {
                return SignalProducer(value: json)
            } else {
                return SignalProducer(error: ReactiveMoyaError.JSONMapping(json).toError())
            }
        })
    }
}

/// Maps a JSON object to an NSDictionary
public func mapJSONDictionary() -> SignalProducer<AnyObject, NSError> -> SignalProducer<NSDictionary, NSError> {
    return { producer in
        return producer |> flatMap(.Latest, { json in
            if let json = json as? NSDictionary {
                return SignalProducer(value: json)
            } else {
                return SignalProducer(error: ReactiveMoyaError.JSONMapping(json).toError())
            }
        })
    }
}

/// Maps the `MoyaResponse` to a String
public func mapString() -> SignalProducer<MoyaResponse, NSError> -> SignalProducer<String, NSError> {
    return { producer in
        return producer |> flatMap(.Latest, { response in
            if let string =  NSString(data: response.data, encoding: NSUTF8StringEncoding) as? String {
                return SignalProducer(value: string)
            } else {
                return SignalProducer(error: ReactiveMoyaError.StringMapping(response).toError())
            }
        })
    }
}
