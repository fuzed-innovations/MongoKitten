import NIO
import MongoKitten
import XCTest

let dbName = "MongoKittenUnitTests"

class CRUDTests : XCTestCase {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
    
    var settings: ConnectionSettings {
        if let mktestEnv = Process().environment?["mk5testenv"] {
            return try! ConnectionSettings(mktestEnv)
        } else if let config = FileManager.default.contents(atPath: ".mktestenv"), let string = String(data: config, encoding: .utf8) {
            return try! ConnectionSettings(string)
        }
        
        return ConnectionSettings(
            authentication: .scramSha1(username: "test", password: ""),
            authenticationSource: nil,
            hosts: [
                .init(hostname: "localhost", port: 27017)
            ],
            targetDatabase: nil,
            useSSL: true,
            verifySSLCertificates: false,
            maximumNumberOfConnections: 1,
            connectTimeout: 0,
            socketTimeout: 0,
            applicationName: "Test MK5"
        )
    }
    
    var connection: Connection!
    
    override func setUp() {
        self.connection = try! Connection.connect(on: group, settings: settings).wait()
        
        try! connection[dbName].drop().wait()
    }
    
//    func testRangeFind() throws {
//        try connection.then { connection -> EventLoopFuture<Void> in
//            let collection = connection["test"]["test"]
//
//            return self.createTestData(n: 128, in: collection).then {
//                let findRange = collection.find(inRange: 10..<22).testRange(count: 12)
//                let findPartialRange = collection.find(inRange: 118...).testRange(startingAt: 118)
//                let findClosedRange = collection.find(inRange: 10...20).testRange()
//
//                return findRange.and(findPartialRange).and(findClosedRange).map { _ in }
//            }
//        }.wait()
//    }
    
    func createTestData(n: Int, in collection: MongoKitten.Collection) -> EventLoopFuture<Void> {
        func nextDocument(index: Int) -> Document {
            return [
                "_id": collection.objectIdGenerator.generate(),
                "n": index
            ]
        }
        
        var future = collection.insert(nextDocument(index: 0))
        
        for index in 1..<n {
            future = future.then { _ in
                return collection.insert(nextDocument(index: index))
            }
        }
        
        return future.map { _ in }
    }
    
    func testHenk() throws {
        let dogs = connection[dbName]["dogs"]
        let owners = connection[dbName]["owners"]
        
        let ownerId = owners.objectIdGenerator.generate()
        dogs.insert(["_id": dogs.objectIdGenerator.generate(), "owner": ownerId])
        owners.insert(["_id": ownerId])
        
        typealias Dog = Document
        typealias Owner = Document
        
        typealias Pair = (Dog, Owner?)
        struct NoOwnerFoundMeh: Error {}
        
        try dogs.find().map { dog -> EventLoopFuture<(Dog, Owner?)> in
            guard let ownerId = dog["owner"] as? ObjectId else {
                throw NoOwnerFoundMeh()
            }
            
            return owners.findOne("_id" == ownerId).map { owner in
                return (dog, owner)
            }
        }.forEachFuture { dog, owner in
            print("dog", dog)
            print("owner", owner)

        }.wait()
        
        try dogs.find().forEach { doc in
            print(doc)
        }.wait()
    }
    
    func testBasicFind() throws {
        let collection = connection[dbName]["test"]
            
        try createTestData(n: 241, in: collection).wait()
        
        var counter = 50
        try collection.find("n" > 50 && "n" < 223).forEach { doc in
            counter += 1
            XCTAssertEqual(doc["n"] as? Int, counter)
        }.wait()
        
        XCTAssertEqual(counter, 222)
        
        counter = 50
        try collection.find("n" > 50).forEach { doc in
            counter += 1
            XCTAssertEqual(doc["n"] as? Int, counter)
            }.wait()
        
        XCTAssertEqual(counter, 240)
        
        counter = 120
        try collection.find("n" > 50).skip(70).limit(30).forEach { doc in
            counter += 1
            XCTAssertEqual(doc["n"] as? Int, counter)
            }.wait()
        
        XCTAssertEqual(counter, 150)
        
        counter = 170
        try collection.find("n" > 50).skip(70).limit(30).sort(["n": .descending]).forEach { doc in
            XCTAssertEqual(doc["n"] as? Int, counter)
            counter -= 1
            }.wait()
        
        XCTAssertEqual(counter, 140)
    }
    
    func testChangeStream() throws {
        let collection = connection[dbName]["test"]
        
        try collection.insert(["_id": ObjectId(), "owner": "Robbert"]).wait()
        
        let changeStream = try collection.aggregate().watch().wait()
        var count = 0
        
        let future = changeStream.forEachAsync { notification in
            count += 1
            XCTAssertEqual(notification.fullDocument?["owner"] as? String, "Joannis")
            return collection.database.connection.eventLoop.newSucceededFuture(result: ())
        }
        
        try collection.insert(["_id": ObjectId(), "owner": "Joannis"]).wait()
        try collection.insert(["_id": ObjectId(), "owner": "Robbert"]).wait()
        
        try future.wait()
        
        XCTAssertEqual(count, 1)
    }
    
//    func testUsage() throws {
//        let total = 152
//        var n = 0
//
//        return try connection.then { connection -> EventLoopFuture<Void> in
//            let collection = connection["test"]["test"]
//
//            return self.createTestData(n: total, in: s).then {
//                return collection.find()
//            }.then { cursor -> EventLoopFuture<Void> in
//                let future = cursor.forEach { doc in
//                    n += 1
//                }
//
//                future.whenSuccess {
//                    XCTAssertEqual(total, n, "The amount of inserts did not match the found results")
//                }
//
//                return future
//            }.then {
//                return collection.count()
//            }.then { count -> EventLoopFuture<Int> in
//                XCTAssertEqual(count, 152, "The count differred from the inserts")
//
//                return collection.deleteAll()
//            }.then { deleted -> EventLoopFuture<Int> in
//                XCTAssertEqual(deleted, 152, "Not everything was deleted")
//
//                return collection.count()
//            }.map { count -> Void in
//                XCTAssertEqual(count, 0, "The count differred from the expected of 0 remaining")
//            }
//        }.wait()
//    }
    
//    func testDistinct() throws {
//        let values = try connection.then { connection -> EventLoopFuture<[Primitive]> in
//            let pets = connection["test"]["pets"]
//
//            // TODO: Real pet names?
//            let a = pets.addPet(named: "A", owner: "Joannis")
//            let b = pets.addPet(named: "B", owner: "Joannis")
//            let c = pets.addPet(named: "C", owner: "Robbert")
//            let d = pets.addPet(named: "D", owner: "Robbert")
//            let e = pets.addPet(named: "E", owner: "Test0")
//            let f = pets.addPet(named: "F", owner: "Test1")
//
//            return a.and(b).and(c).and(d).and(e).and(f).then { _ in
//                return pets.distinct(onKey: "owner")
//            }
//        }.wait()
//
//        let owners = Set(values.compactMap { $0 as? String })
//
//        XCTAssertEqual(owners, ["Joannis", "Robbert", "Test0", "Test1"])
//    }
    
//    func testPipelineUsage() throws {
//        let pets = try connection.then { connection -> EventLoopFuture<Int> in
//            let pets = connection["test"]["pets"]
//
//            // TODO: Real pet names?
//            let a = pets.addPet(named: "A", owner: "Joannis")
//            let b = pets.addPet(named: "B", owner: "Joannis")
//            let c = pets.addPet(named: "C", owner: "Robbert")
//            let d = pets.addPet(named: "D", owner: "Robbert")
//            let e = pets.addPet(named: "E", owner: "Test0")
//            let f = pets.addPet(named: "F", owner: "Test1")
//
//            let inserts = a.and(b).and(c).and(d).and(e).and(f)
//
//            return inserts.then { _ in
//                do {
//                    let query: Query = "owner" == "Joannis" || "owner" == "Robbert"
//                    let pipeline = try Pipeline().match(query).count(writingInto: "pets")
//
//                    return pets.aggregate(pipeline)
//                } catch {
//                    return connection.eventLoop.newFailedFuture(error: error)
//                }
//            }
//        }.wait()
//
//        XCTAssertEqual(pets, 4)
//    }
}

//extension MongoCollection {
//    func addPet(named name: String, owner: String) -> EventLoopFuture<Void> {
//        return self.insert([
//            "_id": self.objectIdGenerator.generate(),
//            "name": name,
//            "owner": owner
//        ]).map { _ in }
//    }
//}
//
//extension EventLoopFuture where T == Cursor<Document> {
//    func testRange(startingAt start: Int64 = 10, count: Int64 = 10) -> EventLoopFuture<Void> {
//        return self.then { cursor in
//            var n: Int64 = start
//
//            return cursor.forEach { document in
//                XCTAssertEqual(document["n"] as? Int64, n)
//                n += 1
//            }.map {
//                XCTAssertEqual(n, start + count)
//            }
//        }
//    }
//}
