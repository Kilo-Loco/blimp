import WebSocketKit
import NIO
import Foundation
import AsyncHTTPClient

let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)

defer {
    try? httpClient.syncShutdown()
}

var eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)

let port: Int = 8080
let promise = eventLoopGroup.next().makePromise(of: [String: Any].self)

enum MyError: LocalizedError {
    case badResponse
}

enum JSONObject {
    case dictionary([String: Any])
}
enum JSONValue {
    case array([JSONValue])
    case boolean(Bool)
    case number(Double)
    case object([String: JSONValue])
    case string(String)
    case null
    
    
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .array(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
    
}

enum OP: Int, ExpressibleByIntegerLiteral {
    case dispatch
    case heartbeat
    case identify
    case statusUpdate
    case voiceStateUpdate
    case voiceServerPing
    case resume
    case reconnect
    case requestGuildMember
    case invalidSession
    case hello
    case heartbeatACK
    
    init(integerLiteral value: IntegerLiteralType) {
        self.init(rawValue: value)!
    }
}

struct Payload {
    let op: OP
    let d: Any
    let t: String?
    let s: Int?
    
    init(
        op: OP,
        d: Any,
        t: String? = nil,
        s: Int? = nil
    ) {
        self.op = op
        self.d = d
        self.t = t
        self.s = s
    }
    
    init?(_ text: String) {
        guard
            let stringData = text.data(using: .utf8),
            let data = try? JSONSerialization.jsonObject(
                with: stringData,
                options: .allowFragments
            ),
            let json = data as? [String: Any],
            let opValue = json["op"] as? Int,
            let op = OP(rawValue: opValue),
            let d = json["d"] as? [String: Any]
        else { return nil }
        
        self.op = op
        self.d = d
        self.t = json["t"] as? String
        self.s = json["s"] as? Int
    }
    
    var json: [String: Any] {
        var dict = ["op": op.rawValue, "d": d]
        
        dict["t"] = t
        dict["s"] = s
        
        return dict
    }
}


struct GatewayIdentifier {
    let token: String
    let intents: Int
    let properties: Properties
    
    var json: [String: Any] {
        [
            "token": token,
            "intents": intents,
            "properties": properties.json
        ]
    }
}

extension GatewayIdentifier {
    struct Properties {
        let os: String
        let browser: String
        let device: String
        
        var json: [String: Any] {
            [
                "$os": os,
                "$browser": browser,
                "$device": device
            ]
        }
    }
    
    init(botToken: String) {
        self.init(
            token: botToken,
            intents: 1 << 9,
            properties: .init(
                os: "macOS",
                browser: "Singularity",
                device: "Singularity"
            )
        )
    }
    
    var payload: String {
        """
        {
          "op": 2,
          "d": {
            "token": "\(token)",
            "intents": \(intents),
            "properties": {
              "$os": "\(properties.os)",
              "$browser": "\(properties.browser)",
              "$device": "\(properties.device)"
            }
          }
        }
        """
    }
    
    func reconnectPayload(forSessionWithId sessionId: String) -> String {
        """
        {
          "op": 6,
          "d": {
            "token": "\(token)",
            "session_id": "\(sessionId)",
            "seq": 1337
          }
        }
        """
    }
}

let gatewayIdentifier = GatewayIdentifier(botToken: "ODIwMDQxOTIzNTUyNjA4MjU4.YEvZjg.y13KmTK2V_eauAH6i6RQF3ZcXt8")

let identifierPayload = Payload(op: .identify, d: gatewayIdentifier.json.description)
let identifierPayloadData = try! JSONSerialization.data(withJSONObject: identifierPayload.json, options: .prettyPrinted)
let idStr = String(data: identifierPayloadData, encoding: .utf8)!

var sid: String?

struct User {
    let avatar: String?
    let discriminator: String
    let id: String
    let publicFlags: Int
    let username: String
    
    init?(_ data: Any) {
        guard
            let dict = data as? [String: Any],
            let discriminator = dict["discriminator"] as? String,
            let id = dict["id"] as? String,
            let publicFlags = dict["public_flags"] as? Int,
            let username = dict["username"] as? String
        else { return nil }
        
        self.avatar = dict["avatar"] as? String
        self.discriminator = discriminator
        self.id = id
        self.publicFlags = publicFlags
        self.username = username
    }
}

struct Message {
    let content: String
    let mentions: [User]
    let channelId: String
    
    
    init?(_ data: Any) {
        guard
            let dict = data as? [String: Any],
            let content = dict["content"] as? String,
            let mentionsArray = dict["mentions"] as? [Any],
            let channelId = dict["channel_id"] as? String
        else { return nil }
        
        self.content = content
        self.mentions = mentionsArray.compactMap(User.init)
        self.channelId = channelId
    }
}

var balance = 0

func sendMessage(with content: String, to channel: String) {
    guard var request = try? HTTPClient.Request(
        url: "https://discord.com/api/v7/channels/\(channel)/messages",
        method: .POST
    ) else {
        print("error making request")
        return
    }
    
    request.headers.add(name: "Content-Type", value: "application/json")
    request.headers.add(name: "Authorization", value: "Bot \(gatewayIdentifier.token)")
    request.body = .data(try! JSONEncoder().encode([
        "content": content,
        "tts": "false"
    ]))
    
    httpClient.execute(request: request).whenComplete { result in
        do {
            let response = try result.get()
            guard response.status == .ok, let body = response.body else { throw MyError.badResponse }
            let stringBody = String(buffer: body)
            print(stringBody)
            
        } catch {
            print(error)
        }
    }
}

func connectSocket(payloadString: String) {
    WebSocket.connect(
        to: "wss://gateway.discord.gg/?v=8&encoding=json",
        headers: ["Authorization": "Bot ODIwMDQxOTIzNTUyNjA4MjU4.YEvZjg.y13KmTK2V_eauAH6i6RQF3ZcXt8"],
        on: eventLoopGroup
    ) { ws in
        ws.onText { _, string in
            print(string)
            guard let payload = Payload(string), let dataDict = payload.d as? [String: Any] else { return }
            
            if payload.t == "READY" {
                sid = dataDict["session_id"] as? String
            } else if payload.t == "MESSAGE_CREATE", let message = Message(payload.d) {
                if !message.mentions.isEmpty {
                    let lowercasedMessageContent = message.content.lowercased()
                    guard lowercasedMessageContent.contains("thank") || lowercasedMessageContent.contains("++") else { return }
                    
                    message.mentions.forEach { user in
                        guard var request = try? HTTPClient.Request(
                            url: "https://htnaclso6jgqdiiaamtffh4tx4.appsync-api.us-west-2.amazonaws.com/graphql",
                            method: .POST
                        ) else {
                            print("error making request")
                            return
                        }
                        
                        request.headers.add(name: "Content-Type", value: "application/graphql")
                        request.headers.add(name: "x-api-key", value: "da2-jldh5fcbffdqvf6w2yj67cjo5m")
                        request.body = .data(try! JSONEncoder().encode(["query": """
                        mutation IncrementBalance {
                          incrementBalanceDiscordUser(input: {id: "\(user.id)"}) {
                            id
                            balance
                          }
                        }
                        """]))
                        
                        httpClient.execute(request: request).whenComplete { result in
                            do {
                                let response = try result.get()
                                guard response.status == .ok, let body = response.body else { throw MyError.badResponse }
                                let stringBody = String(buffer: body)
                                print(stringBody)
                                
                                guard
                                    let stringData = stringBody.data(using: .utf8),
                                    let data = try? JSONSerialization.jsonObject(
                                        with: stringData,
                                        options: .allowFragments
                                    ),
                                    let json = data as? [String: Any],
                                    let payloadData = json["data"] as? [String: [String: Any]]
                                else { return }
                                
                                let databaseUser = payloadData["incrementBalanceDiscordUser"]
                                guard
                                    let userId = databaseUser?["id"] as? String,
                                    let balance = databaseUser?["balance"] as? Int
                                else { return }
                                
                                sendMessage(with: "<@\(userId)> now has \(balance) <:codecoin:822216270971404358>", to: message.channelId)
                                
                            } catch {
                                print(error)
                            }
                        }
                    }
                }
            }
        }
        
        ws.send(payloadString)
        
        ws.onClose.whenComplete { (r) in
            if let sessionId = sid {
                connectSocket(payloadString: gatewayIdentifier.reconnectPayload(forSessionWithId: sessionId))
            }
        }
        
    }.whenFailure { (e) in
        print("ERROR", e)
    }
}

connectSocket(payloadString: gatewayIdentifier.payload)

_  = try promise.futureResult.wait()
