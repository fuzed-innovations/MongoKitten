import Foundation
import BSON
import NIO

#if canImport(_MongoKittenCrypto)
import _MongoKittenCrypto
#endif

/// A SASLStart message initiates a SASL conversation, in our case, used for SCRAM-SHA-xxx authentication.
struct SASLStart: AdministrativeMongoDBCommand {
    private enum CodingKeys: String, CodingKey {
        case saslStart, mechanism, payload
    }
    
    enum Mechanism: String, Codable {
        case scramSha1 = "SCRAM-SHA-1"
        case scramSha256 = "SCRAM-SHA-256"
        
        var md5Digested: Bool {
            return self == .scramSha1
        }
    }
    
    typealias Reply = SASLReply
    
    let namespace: Namespace
    
    let saslStart: Int32 = 1
    let mechanism: Mechanism
    let payload: String
    
    init(namespace: Namespace, mechanism: Mechanism, payload: String) {
        self.namespace = namespace
        self.mechanism = mechanism
        self.payload = payload
    }
}

/// A generic type containing a payload and conversationID.
/// The payload contains an answer to the previous SASLMessage.
///
/// For SASLStart it contains a challenge the client needs to answer
/// For SASLContinue it contains a success or failure state
///
/// If no authentication is needed, SASLStart's reply may contain `done: true` meaning the SASL proceedure has ended
struct SASLReply: ServerReplyDecodableResult {
    var isSuccessful: Bool {
        return ok == 1
    }
    
    let ok: Int
    let conversationId: Int
    let done: Bool
    let payload: String
    
    init(reply: ServerReply) throws {
        let doc = try reply.documents.assertFirst()
        
        if let ok = doc["ok"] as? Double {
            if ok < 1 {
                throw doc.makeError()
            }
            self.ok = Int(ok)
        } else if let ok = doc["ok"] as? Int {
            if ok < 1 {
                throw doc.makeError()
            }
            self.ok = ok
        } else if let ok = doc["ok"] as? Int32 {
            if ok < 1 {
                throw doc.makeError()
            }
            self.ok = Int(ok)
        } else {
            throw doc.makeError()
        }
        
        if let conversationId = doc["conversationId"] as? Int {
            self.conversationId = conversationId
        } else if let conversationId = doc["conversationId"] as? Int32 {
            self.conversationId = Int(conversationId)
        } else {
            throw doc.makeError()
        }
        
        guard let done = doc["done"] as? Bool else {
            throw doc.makeError()
        }
        
        self.done = done
        
        if let payload = doc["payload"] as? String {
            self.payload = payload
        } else  if let payload = doc["payload"] as? Binary, let string = String(data: payload.data, encoding: .utf8) {
            self.payload = string
        } else {
            throw doc.makeError()
        }
    }
    
    func makeResult(on collection: Collection) throws -> SASLReply {
        return self
    }
}

/// A SASLContinue message contains the previous conversationId (from the SASLReply to SASLStart).
/// The payload must contian an answer to the SASLReply's challenge
struct SASLContinue: AdministrativeMongoDBCommand {
    private enum CodingKeys: String, CodingKey {
        case saslContinue, conversationId, payload
    }

    typealias Reply = SASLReply
    
    let namespace: Namespace
    
    let saslContinue: Int32 = 1
    let conversationId: Int
    let payload: String
    
    init(namespace: Namespace, conversation: Int, payload: String) {
        self.namespace = namespace
        self.conversationId = conversation
        self.payload = payload
    }
}

protocol SASLHash: Hash {
    static var algorithm: SASLStart.Mechanism { get }
}

extension SHA1: SASLHash {
    static let algorithm = SASLStart.Mechanism.scramSha1
}

extension SHA256: SASLHash {
    static let algorithm = SASLStart.Mechanism.scramSha256
}

extension Connection {
    /// Handles a SCRAM authentication flow
    ///
    /// The Hasher `H` specifies the hashing algorithm used with SCRAM.
    func authenticateSASL<H: SASLHash>(hasher: H, namespace: Namespace, username: String, password: String) -> EventLoopFuture<Void> {
        let context = SCRAM<H>(hasher)
        
        do {
            let rawRequest = try context.authenticationString(forUser: username)
            let request = Data(rawRequest.utf8).base64EncodedString()
            let command = SASLStart(namespace: namespace, mechanism: H.algorithm, payload: request)
            
            // NO session must be used here: https://github.com/mongodb/specifications/blob/master/source/sessions/driver-sessions.rst#when-opening-and-authenticating-a-connection
            // Forced on the current connection
            return self._execute(command: command, session: nil, transaction: nil).then { serverReply in
                do {
                    let reply = try SASLReply(reply: serverReply)
                    
                    if reply.done {
                        return self.eventLoop.newSucceededFuture(result: ())
                    }
                    
                    let preppedPassword: String
                    
                    if H.algorithm.md5Digested {
                        var md5 = MD5()
                        let credentials = "\(username):mongo:\(password)"
                        preppedPassword = md5.hash(bytes: Array(credentials.utf8)).hexString
                    } else {
                        preppedPassword = password
                    }
                    
                    let challenge = try reply.payload.base64Decoded()
                    let rawResponse = try context.respond(toChallenge: challenge, password: preppedPassword)
                    let response = Data(rawResponse.utf8).base64EncodedString()
                    
                    let next = SASLContinue(
                        namespace: namespace,
                        conversation: reply.conversationId,
                        payload: response
                    )
                    
                    return self._execute(command: next, session: nil, transaction: nil).then { serverReply in
                        do {
                            let reply = try SASLReply(reply: serverReply)
                            
                            let successReply = try reply.payload.base64Decoded()
                            try context.completeAuthentication(withResponse: successReply)
                            
                            if reply.done {
                                return self.eventLoop.newSucceededFuture(result: ())
                            } else {
                                let final = SASLContinue(
                                    namespace: namespace,
                                    conversation: reply.conversationId,
                                    payload: ""
                                )
                                
                                return self._execute(command: final, session: nil, transaction: nil).thenThrowing { serverReply in
                                    let reply = try SASLReply(reply: serverReply)
                                    
                                    guard reply.done else {
                                        throw MongoKittenError(.authenticationFailure, reason: .malformedAuthenticationDetails)
                                    }
                                }
                            }
                        } catch {
                            return self.eventLoop.newFailedFuture(error: error)
                        }
                    }
                } catch {
                    return self.eventLoop.newFailedFuture(error: error)
                }
            }
        } catch {
            return self.eventLoop.newFailedFuture(error: error)
        }
    }
}

extension String {
    /// Decodes a base64 string into another String
    func base64Decoded() throws -> String {
        guard
            let data = Data(base64Encoded: self),
            let string = String(data: data, encoding: .utf8)
        else {
            throw MongoKittenError(.authenticationFailure, reason: .scramFailure)
        }
        
        return string
    }
}
