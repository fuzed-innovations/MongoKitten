import Foundation

fileprivate extension Bool {
    init?(queryValue: Substring?) {
        switch queryValue {
        case nil:
            return nil
        case "0", "false", "FALSE":
            self = false
        default:
            self = true
        }
    }
}

/// Describes the settings for a MongoDB connection, most of which can be represented in a connection string
public struct ConnectionSettings: Equatable {
    
    /// The authentication details to use with the database
    public enum Authentication: Equatable {
        /// Unauthenticated
        case unauthenticated
        
        /// SCRAM-SHA1 mechanism
        case scramSha1(username: String, password: String)
        
        /// MongoDB Challenge Response mechanism
        case mongoDBCR(username: String, password: String)
    }
    
    /// Defines a MongoDB host
    public struct Host: Equatable {
        
        /// The hostname, like "localhost", "example.com" or "127.0.0.1"
        public var hostname: String
        
        /// The port. The default MongoDB port is 27017
        public var port: UInt16
        
        /// Initializes a new `Host` instance
        ///
        /// - parameter hostname: The hostname
        /// - parameter port: The port
        public init(hostname: String, port: UInt16) {
            self.hostname = hostname
            self.port = port
        }
    }
    
    /// The authentication details (mechanism + credentials) to use
    public var authentication: Authentication
    
    /// Specify the database name associated with the user’s credentials. authSource defaults to the database specified in the connection string.
    /// For authentication mechanisms that delegate credential storage to other services, the authSource value should be $external as with the PLAIN (LDAP) and GSSAPI (Kerberos) authentication mechanisms.
    public var authenticationSource: String?
    
    /// Hosts to connect to
    public var hosts: [Host]
    
    /// When true, SSL will be used
    public var useSSL: Bool = false
    
    /// When true, SSL certificates will be validated
    public var verifySSLCertificates: Bool = true
    
    /// The maximum number of connections allowed
    public var maximumNumberOfConnections: Int = 1
    
    /// The connection timeout, in seconds. Defaults to 5 minutes.
    public var connectTimeout: TimeInterval = 300
    
    /// The time in seconds to attempt a send or receive on a socket before the attempt times out. Defaults to 5 minutes.
    public var socketTimeout: TimeInterval = 300
    
    /// The target path
    public var targetDatabase: String?
    
    /// Initializes a new connection settings instacen.
    ///
    /// - parameter authentication: See `ConnectionSettings.Authentication`
    /// - parameter authenticationSource: See `ConnectionSettings.authenticationSource`
    /// - parameter hosts: Hosts to connect to
    /// - parameter targetDatabase: The target path
    /// - parameter useSSL: When true, SSL will be used
    /// - parameter verifySSLCertificates: When true, SSL certificates will be validated
    /// - parameter maximumNumberOfConnections: The maximum number of connections allowed
    /// - parameter connectTimeout: See `ConnectionSettings.connectTimeout`
    /// - parameter socketTimeout: See `ConnectionSettings.socketTimeout`
    public init(authentication: Authentication, authenticationSource: String? = nil, hosts: [Host], targetDatabase: String? = nil, useSSL: Bool = false, verifySSLCertificates: Bool = true, maximumNumberOfConnections: Int = 1, connectTimeout: TimeInterval = 300, socketTimeout: TimeInterval = 300) {
        self.authentication = authentication
        self.authenticationSource = authenticationSource
        self.hosts = hosts
        self.targetDatabase = targetDatabase
        self.useSSL = useSSL
        self.verifySSLCertificates = verifySSLCertificates
        self.maximumNumberOfConnections = maximumNumberOfConnections
        self.connectTimeout = connectTimeout
        self.socketTimeout = socketTimeout
    }
    
    /// Parses the given `uri` into the ConnectionSettings
    /// `mongodb://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]`
    ///
    /// Supported options include:
    ///
    /// - `authMechanism`: Specifies the authentication mechanism to use, see `ConnectionSettings.Authentication`
    /// - `authSource`: The authentication source, see the documenation on `ConnectionSettings.authenticationSource` for details
    /// - `ssl`: SSL will be used when set to true
    /// - `sslVerify`: When set to `0` or `false`, the SSL certificate will not be verified
    ///
    /// For query options, `0`, `false` and `FALSE` are interpreted as false. All other values, including no value at all (when the key is included), are interpreted as true.
    public init(_ uri: String) throws {
        var uri = uri
        
        // First, remove the mongodb:// scheme
        guard uri.starts(with: "mongodb://") else {
            throw MongoKittenError(.invalidURI, reason: .missingMongoDBScheme)
        }
        
        uri.removeFirst("mongodb://".count)
        
        // Split the string in parts before and after the authentication details
        let parts = uri.split(separator: "@")
        
        guard parts.count <= 2 else {
            throw MongoKittenError(.invalidURI, reason: .uriIsMalformed)
        }
        
        let uriContainsAuthenticationDetails = parts.count == 2
        
        // The hosts part, for now, is everything after the authentication details
        var hostsPart = uriContainsAuthenticationDetails ? parts[1] : parts[0]
        var queryParts = hostsPart.split(separator: "?")
        hostsPart = queryParts.removeFirst()
        let queryString = queryParts.first
        
        // Split the path
        let pathParts = hostsPart.split(separator: "/")
        hostsPart = pathParts[0]
        
        if pathParts.count > 1 {
            self.targetDatabase = String(pathParts[1])
        }
        
        // Parse all queries
        let queries: [Substring: Substring]
        if let queryString = queryString {
            queries = Dictionary(uniqueKeysWithValues: queryString.split(separator: "&").map { queryItem in
                // queryItem can be either like `someOption` or like `someOption=abc`
                let queryItemParts = queryItem.split(separator: "=", maxSplits: 1)
                let queryItemName = queryItemParts[0]
                let queryItemValue = queryItemParts.count > 1 ? queryItemParts[1] : ""
                
                return (queryItemName, queryItemValue)
            })
        } else {
            queries = [:]
        }
        
        // Parse the authentication details, if included
        if uriContainsAuthenticationDetails {
            let authenticationString = parts[0]
            let authenticationParts = authenticationString.split(separator: ":")
            
            guard authenticationParts.count == 2 else {
                throw MongoKittenError(.invalidURI, reason: .malformedAuthenticationDetails)
            }
            
            guard let username = authenticationParts[0].removingPercentEncoding, let password = authenticationParts[1].removingPercentEncoding else {
                throw MongoKittenError(.invalidURI, reason: .malformedAuthenticationDetails)
            }
            
            let mechanism = queries["authMechanism"]?.uppercased() ?? "SCRAM_SHA_1"
            
            switch mechanism {
            case "SCRAM_SHA_1":
                self.authentication = .scramSha1(username: username, password: password)
            case "MONGODB_CR":
                self.authentication = .mongoDBCR(username: username, password: password)
            default:
                throw MongoKittenError(.invalidURI, reason: .unsupportedAuthenticationMechanism)
            }
        } else {
            self.authentication = .unauthenticated
        }
        
        /// Parse the hosts, which may or may not contain a port number
        self.hosts = try hostsPart.split(separator: ",").map { hostString in
            let splitHost = hostString.split(separator: ":", maxSplits: 1)
            let specifiesPort = splitHost.count == 2
            let port: UInt16
            
            if specifiesPort {
                let specifiedPortString = splitHost[1]
                guard let specifiedPort = UInt16(specifiedPortString) else {
                    throw MongoKittenError(.invalidURI, reason: .invalidPort)
                }
                
                port = specifiedPort
            } else {
                port = 27017
            }
            
            return Host(hostname: String(splitHost[0]), port: port)
        }
        
        // Parse various options
        if let authSource = queries["authSource"] {
            self.authenticationSource = String(authSource)
        }
        
        if let useSSL = Bool(queryValue: queries["ssl"]) {
            self.useSSL = useSSL
        }
        
        if let sslVerify = Bool(queryValue: queries["sslVerify"]) {
            self.verifySSLCertificates = sslVerify
        }
        
        if let maxConnectionsOption = queries["maxConnections"], let maxConnectionsNumber = Int(maxConnectionsOption), maxConnectionsNumber >= 0 {
            self.maximumNumberOfConnections = maxConnectionsNumber
        }
        
        if let connectTimeoutMSOption = queries["connectTimeoutMS"], let connectTimeoutMSNumber = Int(connectTimeoutMSOption), connectTimeoutMSNumber > 0 {
            self.connectTimeout = TimeInterval(connectTimeoutMSNumber) / 1000
        }
        
        if let socketTimeoutMSOption = queries["socketTimeoutMS"], let socketTimeoutMSNumber = Int(socketTimeoutMSOption), socketTimeoutMSNumber > 0 {
            self.socketTimeout = TimeInterval(socketTimeoutMSNumber) / 1000
        }
    }
    
}