import NIO
import Foundation

/// A reference to a collection in a `Database`.
///
/// MongoDB stores documents in collections. Collections are analogous to tables in relational databases.
public class Collection: FutureConvenienceCallable {
    // MARK: Properties
    internal var transaction: Transaction?
    
    /// The name of the collection
    public let name: String
    
    /// The database this collection resides in
    public let database: Database
    
    public var eventLoop: EventLoop {
        return pool.eventLoop
    }
    
    internal func makeTransactionQueryOptions() -> TransactionQueryOptions? {
        guard let transaction = transaction else {
            return nil
        }
        
        defer {
            transaction.started = true
            transaction.active = true
        }
        
        return TransactionQueryOptions(
            id: transaction.id,
            startTransaction: !transaction.started,
            autocommit: transaction.autocommit ?? false
        )
    }
    
    internal var session: ClientSession
    
    internal var pool: _ConnectionPool {
        return self.database.session.pool
    }
    
    /// The connection's ObjectId generator
    public var objectIdGenerator: ObjectIdGenerator {
        return pool.sharedGenerator
    }
    
    /// The full collection namespace: "databasename.collectionname"
    public var fullName: String {
        return "\(self.database.name).\(self.name)"
    }
    
    internal var namespace: Namespace {
        return Namespace(to: self.name, inDatabase: self.database.name)
    }
    
    /// Initializes this collection with by the database it's in and the collection name
    internal init(named name: String, in database: Database) {
        self.name = name
        self.database = database
        self.session = database.session
    }
    
    // MARK: General execution of commands
    
    public func execute(command: InsertCommand) -> EventLoopFuture<InsertReply> {
        return command.execute(on: self)
    }
    
    public func execute(command: UpdateCommand) -> EventLoopFuture<UpdateReply> {
        return command.execute(on: self)
    }
    
    public func execute(command: DeleteCommand) -> EventLoopFuture<Int> {
        return command.execute(on: self)
    }
    
    // MARK: Reading from a collection
    
    /// Executes a query on the collection.
    ///
    /// To perform further refinement, use the methods on `FindCursor`, like:
    ///
    /// - `FindCursor.limit(...)`
    /// - `FindCursor.skip(...)`
    /// - `FindCursor.sort(...)`
    ///
    /// - parameter query: The query to execute. Defaults to an empty query that returns every document.
    /// - returns: A `FindCursor` that can be used to fetch results, or perform additional refinement of the results
    public func find(_ query: Query = [:]) -> FindCursor {
        return FindCursor(command: FindCommand(filter: query, on: self), on: self)
    }
    
    /// Executes a query on the collection, and returns the first result.
    ///
    /// - see: `Query`
    /// - parameter query: The query to execute. Defaults to an empty query that returns every document.
    /// - returns: The first result
    public func findOne<D: Decodable>(_ query: Query = [:], as type: D.Type) -> EventLoopFuture<D?> {
        var command = FindCommand(filter: query, on: self)
        command.limit = 1
        
        return FindCursor(command: command, on: self).decode(type).getFirstResult()
    }
    
    /// Executes a query on the collection, and returns the first result.
    ///
    /// - see: `Query`
    /// - parameter query: The query to execute. Defaults to an empty query that returns every document.
    /// - returns: The first result
    public func findOne(_ query: Query = [:]) -> EventLoopFuture<Document?> {
        var command = FindCommand(filter: query, on: self)
        command.limit = 1
        
        return FindCursor(command: command, on: self).getFirstResult()
    }
    
    /// Counts the number of documents in a collection or a view for the given query.
    ///
    /// - parameter query: The query to execute. Defaults to an empty query that counts every document.
    /// - returns: The number of documents matching the given query.
    public func count(_ query: Query? = nil) -> EventLoopFuture<Int> {
        return CountCommand(query, in: self).execute(on: self)
    }
    
    /// Finds the distinct values for a specified field across a single collection. distinct returns a document that contains an array of the distinct values. The return document also contains an embedded document with query statistics and the query plan.
    ///
    /// - see: https://docs.mongodb.com/manual/reference/command/distinct/index.html
    ///
    /// - parameter key: The field for which to return distinct values.
    /// - parameter query: A query that specifies the documents from which to retrieve the distinct values.
    public func distinct(onKey key: String, where filter: Query? = nil) -> EventLoopFuture<[Primitive]> {
        var distinct = DistinctCommand(onKey: key, into: self)
        distinct.query = filter
        return distinct.execute(on: self)
    }
    
    /// Calculates aggregate values for the data in a collection or a view.
    ///
    /// You add pipeline stages to the aggregation command by calling methods on the returned cursor. For example:
    ///
    /// ```swift
    /// collection.aggregate()
    ///     .match("status" == "A")
    ///     .group(id: "$cust_id", ["total": .sum("$amount"))
    ///     .forEach { result in ... }
    /// ```
    ///
    /// - see: https://docs.mongodb.com/manual/core/aggregation-pipeline/index.html
    /// - see: https://docs.mongodb.com/manual/reference/command/aggregate/index.html
    ///
    /// - parameter comment: An arbitrary string to help trace the operation through the database profiler, currentOp, and logs.
    public func aggregate(comment: String? = nil) -> AggregateCursor<Document> {
        let cursor = AggregateCursor(on: self)
        
        if let comment = comment {
            cursor.operation.comment = comment
        }
        
        return cursor
    }
    
    // MARK: Inserting documents
    
    /// Inserts one document into the collection
    ///
    /// - parameter document: The document to insert into the collection
    /// - returns: A reply containing the status of the insert
    /// - see: https://docs.mongodb.com/manual/reference/command/insert/index.html
    @discardableResult
    public func insert(_ document: Document) -> EventLoopFuture<InsertReply> {
        return insert(documents: [document])
    }
    
    /// Inserts one or more documents into the collection
    ///
    /// - parameter documents: The documents to insert into the collection
    /// - returns: A reply containing the status of all inserts
    /// - see: https://docs.mongodb.com/manual/reference/command/insert/index.html
    @discardableResult
    public func insert(documents: [Document]) -> EventLoopFuture<InsertReply> {
        return InsertCommand(documents, into: self).execute(on: self)
    }
    
    // MARK: Removing documents
    
    /// Deletes all documents in the collection that match the given query.
    ///
    /// - warning: If you provide no query, all documents in the collection will be deleted
    /// - parameter query: The filter to apply. Defaults to an empty query, deleting every document.
    /// - returns: The number of documents removed
    public func deleteAll(where query: Query) -> EventLoopFuture<Int> {
        let delete = DeleteCommand.Single(matching: query, limit: .all)

        return DeleteCommand([delete], from: self).execute(on: self)
    }
    
    /// Deletes one document that matches the given query.
    ///
    /// - parameter query: The filter to apply. Defaults to an empty query
    /// - returns: The number of documents removed
    public func deleteOne(where query: Query) -> EventLoopFuture<Int> {
        let delete = DeleteCommand.Single(matching: query, limit: .one)
        
        return DeleteCommand([delete], from: self).execute(on: self)
    }
    
    // MARK: Performing updates
    
    /// Updates the document(s) matching the given query to the given `document`.
    ///
    /// ## Behavior
    ///
    /// The `document` can contain either all update operator expressions or all field:value expressions.
    ///
    /// ### Update Operator Expressions
    ///
    /// If the `document` contains all update operator expressions, as in:
    ///
    /// ```
    /// {
    ///     $set: { status: "D" },
    ///     $inc: { quantity: 2 }
    /// }
    /// ```
    ///
    /// Then, the update command updates only the corresponding fields in the document.
    ///
    /// ### `Field: Value` Expressions
    ///
    /// If the `document` contains only `field:value` expressions, as in:
    ///
    /// ```
    /// {
    ///     status: "D",
    ///     quantity: 4
    /// }
    /// ```
    ///
    /// Then the update command replaces the matching document with the update document. The update command can only replace a single matching document; i.e. the multi field cannot be true. The update command does not replace the _id value.
    ///
    /// - see: https://docs.mongodb.com/manual/reference/command/update/index.html#update-command-behaviors
    /// - parameter query: The filter to apply
    /// - parameter document: The document to replace the target document(s) with
    /// - parameter multiple: If set to `true`, more than one document may be updated
    @discardableResult
    public func update(where query: Query, to document: Document, multiple: Bool? = nil) -> EventLoopFuture<UpdateReply> {
        return UpdateCommand(query, to: document, in: self, multiple: multiple).execute(on: self)
    }
    
    /// Updates the document(s) matching the given query to the given `document`. If no document matches the given query, the document will be inserted into the collection.
    ///
    /// - parameter query: The filter to apply
    /// - parameter document: The document to insert or to replace the target document with
    @discardableResult
    public func upsert(where query: Query, to document: Document) -> EventLoopFuture<UpdateReply> {
        var update = UpdateCommand.Single(matching: query, to: document)
        update.upsert = true
        
        return UpdateCommand(update, in: self).execute(on: self)
    }
    
    /// Updates the document(s) matching the given query, setting the values given in `set`.
    ///
    /// Under the hood, this will generate an update command using `$set` and `$unset`.
    ///
    /// - parameter query: The filter to apply
    /// - parameter set: A dictionary containing keys and values to set. The key may use dot notation, e.g. `foo.bar` to access nested
    ///                     values. To remove the value for a certain key, specify `nil` as its value.
    /// - parameter multiple: If set to `true`, more than one document may be updated
    @discardableResult
    public func update(where query: Query, setting set: [String: Primitive?], multiple: Bool? = nil) -> EventLoopFuture<UpdateReply> {
        guard set.count > 0 else {
            return eventLoop.newFailedFuture(error: MongoKittenError(.cannotFormCommand, reason: .nothingToDo))
        }
        
        var setQuery = Document()
        var unsetQuery = Document()
        
        for (key, value) in set {
            if let value = value {
                setQuery[key] = value
            } else {
                unsetQuery[key] = ""
            }
        }
        
        let updateDocument: Document = [
            "$set": setQuery.count > 0 ? setQuery : nil,
            "$unset": unsetQuery.count > 0 ? unsetQuery : nil
        ]
        
        return self.update(where: query, to: updateDocument, multiple: multiple)
    }
    
    public var indexes: CollectionIndexes {
        return CollectionIndexes(for: self)
    }
    
    public func drop() -> EventLoopFuture<Void> {
        let command = AdministrativeCommand(command: DropCollection(named: self.name), on: database.cmd)
        
        return command.execute(on: self).map { _ in }
    }
}
