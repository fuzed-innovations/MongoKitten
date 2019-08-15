import NIO

public struct FindCommand: ReadCommand {
    typealias Reply = CursorReply
    
    internal var namespace: Namespace {
        return find
    }
    
    /// This variable _must_ be the first encoded value, so keep it above all others
    internal let find: Namespace
    
    public var filter: Query?
    public var sort: Sort?
    public var projection: Projection?
    public var skip: Int?
    public var limit: Int?
    public var readConcern: ReadConcern?
    
    public init(filter: Query?, on collection: Collection) {
        self.filter = filter
        self.find = collection.namespace
    }
}

public struct CursorSettings: Encodable {
    var batchSize: Int?
}

struct CursorReply: ServerReplyDecodableResult {
    struct CursorDetails: Codable {
        var id: Int64
        var ns: String
        var firstBatch: [Document]
    }
    
    var isSuccessful: Bool {
        return ok == 1
    }
    
    internal let cursor: CursorDetails
    private let ok: Int
    
    func makeResult(on collection: Collection) throws -> Cursor {
        return Cursor(reply: self, in: collection)
    }
}

/// A cursor that results from a `FindCommand`
public final class FindCursor: QueryCursor {
    /// The FindCursor alays results in a `Document`
    public typealias Element = Document
    
    /// The batch size
    public var batchSize = 101
    
    /// The collection this cursor applies to
    public let collection: Collection
    private var command: FindCommand
    
    public init(command: FindCommand, on collection: Collection) {
        self.command = command
        self.collection = collection
    }
    
    public func execute() -> EventLoopFuture<FinalizedCursor<FindCursor>> {
        let options = collection.makeTransactionQueryOptions()
        
        return self.collection.database.session.execute(command: self.command, transaction: options).mapToResult(for: collection).map { cursor in
            return FinalizedCursor(basedOn: self, cursor: cursor)
        }
    }
    
    public func setBatchSize(_ batchSize: Int) -> FindCursor {
        self.batchSize = batchSize
        return self
    }
    
    public func transformElement(_ element: Document) throws -> Document {
        return element
    }
    
    public func limit(_ limit: Int) -> FindCursor {
        self.command.limit = limit
        return self
    }
    
    public func skip(_ skip: Int) -> FindCursor {
        self.command.skip = skip
        return self
    }
    
    public func project(_ projection: Projection) -> FindCursor {
        self.command.projection = projection
        return self
    }
    
    public func sort(_ sort: Sort) -> FindCursor {
        self.command.sort = sort
        return self
    }
}
