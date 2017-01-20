//
//  AggregationTests.swift
//  MongoKitten
//
//  Created by Laurent Gaches on 17/01/2017.
//
//


import XCTest
import MongoKitten
import CryptoKitten
import Dispatch

class AggregationTests: XCTestCase {
    static var allTests: [(String, (AggregationTests) -> () throws -> Void)] {
        return [
            ("testGeoNear", testGeoNear),
            ("testAggregate", testAggregate),
            ("testFacetAggregate", testFacetAggregate),
            ("testAggregateLookup", testAggregateLookup)            
        ]
    }

    override func setUp() {
        super.setUp()
        do {
            try TestManager.clean()
        } catch {
            fatalError("\(error)")
        }
    }

    override func tearDown() {

        try! TestManager.disconnect()
    }

    func testGeoNear() throws {
        let zips = TestManager.db["zips"]
        try zips.createIndex(named: "loc_index", withParameters: .geo2dsphere(field: "loc"))
        let position = try Position(values: [-72.844092,42.466234])
        let near = Point(coordinate: position)

        let geoNearOption = GeoNearOption(near: near, spherical: true, distanceField: "dist.calculated", maxDistance: 10000.0)

        let geoNearStage = AggregationPipeline.Stage.geoNear(geoNearOption: geoNearOption)

        let pipeline: AggregationPipeline = [geoNearStage]

        let results = Array(try zips.aggregate(pipeline: pipeline))

        XCTAssertEqual(results.count, 6)
    }


    func testAggregate() throws {
        let pipeline: AggregationPipeline = [
            .grouping("$state", computed: ["totalPop": .sumOf("$pop")]),
            .matching("totalPop" > 10_000_000),
            .sortedBy(["totalPop": .ascending]),
            .projecting(["_id": false, "totalPop": true]),
            .skipping(2)
        ]

        let cursor = try TestManager.db["zips"].aggregate(pipeline: pipeline)

        var count = 0
        var previousPopulation = 0
        for populationDoc in cursor {
            let population = populationDoc["totalPop"] as Int? ?? -1

            guard population > previousPopulation else {
                XCTFail()
                continue
            }

            guard populationDoc[raw: "_id"] == nil else {
                XCTFail()
                continue
            }

            previousPopulation = population

            count += 1
        }

        XCTAssertEqual(count, 5)

        let pipeline2: AggregationPipeline = [
            .grouping("$state", computed: ["totalPop": .sumOf("$pop")]),
            .matching("totalPop" > 10_000_000),
            .sortedBy(["totalPop": .ascending]),
            .projecting(["_id": false, "totalPop": true]),
            .skipping(2),
            .limitedTo(3),
            .counting(insertedAtKey: "results"),
            .addingFields(["topThree": true])
        ]

        do {
            let result = Array(try TestManager.db["zips"].aggregate(pipeline: pipeline2)).first

            guard let resultCount = result?["results"] as Int?, resultCount == 3, result?["topThree"] as Bool? == true else {
                XCTFail()
                return
            }
        } catch MongoError.invalidResponse(let response) {
            XCTAssertEqual(response.first?[raw: "code"]?.int, 16436)
        }
        // TODO: Test $out, $lookup, $unwind
    }

    func testFacetAggregate() throws {
        if TestManager.server.buildInfo.version < Version(3, 4, 0) {
            return
        }
        
        let pipeline: AggregationPipeline = [
            .grouping("$state", computed: ["totalPop": .sumOf("$pop")]),
            .sortedBy(["totalPop": .ascending]),
            .facet([
                "count": [
                    .counting(insertedAtKey: "resultCount"),
                    .projecting(["resultCount": true])
                ],
                "totalPop": [
                    .grouping(Null(), computed: ["population": .sumOf("$totalPop")])
                ]
                ])
        ]

        guard let result = Array(try TestManager.db["zips"].aggregate(pipeline: pipeline)).first else {
            XCTFail()
            return
        }

        XCTAssertEqual(result["count", 0, "resultCount"] as Int?, 51)
        XCTAssertEqual(result["totalPop", 0, "population"] as Int?, 248408400)
    }

    func testAggregateLookup() throws {
        if TestManager.server.buildInfo.version < Version(3, 2, 0) {
            return
        }
        
        let orders = TestManager.db["orders"]
        let inventory = TestManager.db["inventory"]

        try orders.drop()
        try inventory.drop()

        let orderDocument: Document = ["_id": 1, "item": "MON1003", "price": 350, "quantity": 2, "specs": [ "27 inch", "Retina display", "1920x1080" ] as Document, "type": "Monitor"]
        let orderId = try orders.insert(orderDocument)
        XCTAssertEqual(orderId.int, 1)

        let inventoryDocument1: Document = ["_id": 1, "sku": "MON1003", "type": "Monitor", "instock": 120, "size": "27 inch", "resolution": "1920x1080"]
        let inventoryDocument2: Document = ["_id": 2, "sku": "MON1012", "type": "Monitor", "instock": 85, "size": "23 inch", "resolution": "1280x800"]
        let inventoryDocument3: Document = ["_id": 3, "sku": "MON1031", "type": "Monitor", "instock": 60, "size": "23 inch", "display_type": "LED"]

        let inventory1 = try inventory.insert(inventoryDocument1)
        let inventory2 = try inventory.insert(inventoryDocument2)
        let inventory3 = try inventory.insert(inventoryDocument3)

        XCTAssertEqual(inventory1.int, 1)
        XCTAssertEqual(inventory2.int, 2)
        XCTAssertEqual(inventory3.int, 3)

        let unwind = AggregationPipeline.Stage.unwind(atPath: "$specs")
        let lookup = AggregationPipeline.Stage.lookup(fromCollection: inventory, localField: "specs", foreignField: "size", as: "inventory_docs")
        let match = AggregationPipeline.Stage.matching(["inventory_docs": ["$ne":[] as Document] as Document] as Document)
        let pipe = AggregationPipeline(arrayLiteral: unwind, lookup, match)

        do {
            let cursor = try orders.aggregate(pipeline: pipe)
            let results = cursor.array
            XCTAssertEqual(results.count, 1)
            if results.count == 1 {
                let document = results[0]
                XCTAssertEqual(document[raw: "item"]?.string, "MON1003")
                XCTAssertEqual(document[raw: "price"]?.int, 350)
                XCTAssertEqual(document[raw: "inventory_docs"]?.documentValue?.arrayValue.count, 1)
            }
        } catch let error as MongoError {
            XCTFail(error.localizedDescription)
        }
    }
}
