<p align="center">

![OpenKitten](assets/ReadmeHeader.svg)

![OpenKitten](assets/Descriptions.gif)

[Installation](#-installation) | [Basic usage](#-basic-usage) | [About BSON](#-about-bson--documents) | [Codable](#-codable) | [Community](#-community) | [How to help](#-how-to-help)

</p>

A fast, pure swift [MongoDB](https://mongodb.com) driver based on [Swift NIO](https://github.com/apple/swift-nio) built for Server Side Swift. It features a great API and a battle-tested core. Supporting both MongoDB in server and embedded environments.

⭐️ Please leave a star to support MongoKitten – it really helps!

# 🕶 Installation

## Set up MongoDB server

<details>
<summary>If you haven't already, you should set up a MongoDB server to get started with MongoKitten</summary>

For development, this can be on your local machine.

Install MongoDB for [Ubuntu](https://docs.mongodb.com/master/tutorial/install-mongodb-on-ubuntu/), [macOS](https://docs.mongodb.com/master/tutorial/install-mongodb-on-os-x/) or [any other supported Linux Distro](https://docs.mongodb.com/master/administration/install-on-linux/).

Alternatively, make use of a DAAS (Database-as-a-service) like [MongoDB Atlas](https://cloud.mongodb.com), [MLab](https://mlab.com), [IBM Cloud](https://cloud.ibm.com/catalog/services/databases-for-mongodb) or any other of the many services.
</details>

If you're aiming at using MongoKitten Mobile, scroll down!

## Add MongoKitten to your Swift project 🚀

MongoKitten supports the [Swift Package Manager](https://swift.org/getting-started/#using-the-package-manager) for server-side applications. Add MongoKitten to your dependencies in your **Package.swift** file:

`.package(url: "https://github.com/OpenKitten/MongoKitten.git", from: "5.0.0")`

Also, don't forget to add `"MongoKitten"` as a dependency for your target.

### Mobile [BETA]

MongoKitten now also supports embedded MongoDB databases in beta.

For MongoKitten mobile we rely on [Cocoapods](https://cocoapods.org/). This is not officially supported for using MongoKitten yet, but you can get started by simply add this to your **Podfile**:

`pod 'MongoKitten'`

# 🚲 Basic usage

## Connect to your database

```swift
import MongoKitten

let db = try Database.synchronousConnect("mongodb://localhost/my_database")
```

And for embedded databases:

```swift
// WARNING: Force unwrap will crash your application on failure
let mongo = try! MobileDatabase(settings: .default())
```

## Vapor 3 users should register the database as a service.
In your `configure.swift`
```swift
extension MongoKitten.Database: Service {}

let connectionURI = "mongodb://localhost"

services.register(MongoKitten.Database.self) { container -> MongoKitten.Database in
    return try MongoKitten.Database.lazyConnect(connectionURI, on: container.eventLoop)
}
```
Now in a route handler you have access to your database like any other service:
```swift
struct ServerLanguage: Content {
   var language: String
}

func fetchTheBestServerLanguage(_ req: Request) throws -> EventLoopFuture<ServerLanguage> {
    let db = try req.make(MongoKitten.Database.self)
	
    return db["server_languages"].findOne("language" == "swift").map { doucment in
        guard let theBest = document else {
            throw Abort(.internalServerError, reason: "Couldn't find the best, Node.JS is your future 🤢")
	}
	return try BSONDecoder().decode(ServerLanguage.self, from: theBest)
    }
}
```

### Note on URIs

MongoKitten [does not yet support](https://github.com/OpenKitten/MongoKitten/issues/172#issuecomment-468302085) MongoDB v3.6 connection URIs. You'll need to use the old connection URI format.

If you're unsure; the connection string starting with `mongodb+srv://` is a 3.6 connection URI, whereas URIs starting with `mongodb://` are an older format.

## NIO Futures

<details>
<summary>MongoKitten relies on Swift NIO to provide support for asynchronous operations. All MongoKitten operations that talk to the server are asynchronous, and return an EventLoopFuture of some kind.</summary>

You can learn all about NIO by reading [its readme](https://github.com/apple/swift-nio/blob/master/README.md) or [the article on RayWenderlich.com](https://www.raywenderlich.com/1124580-a-simple-guide-to-async-on-the-server), but here are the basics:

Asynchronous operations return a future. NIO implements futures in the [`EventLoopFuture<T>`](https://apple.github.io/swift-nio/docs/current/NIO/Classes/EventLoopFuture.html) type. An `EventLoopFuture` is a holder for a result that will be provided later. The result of the future can either be successful yielding a result of `T`, or unsuccessful with a result of a Swift `Error`. This is the asynchronous representation of a successful `return` or a thrown error.

If you're using [Vapor](https://vapor.codes), please refer to their [Async documentation](https://docs.vapor.codes/3.0/async/overview/). Vapor's Async module provides additional helpers on top of NIO, that make working with instances of `EventLoopFuture<T>` easier.

If you use Vapor or another Swift-NIO based web framework, *never* use the `wait()` function on `EventLoopFuture` instances.
</details>

## CRUD (Create, Read, Update, Delete)

```swift
// The collection "users" in your database
let users = db["users"]
```

### Create (insert)

```swift
let myUser: Document = ["username": "kitty", "password": "meow"]

let future: Future<InsertReply> = users.insert(myUser)

future.whenSuccess { _ in
	print("Inserted!")
}

future.whenFailure { error in
	print("Insertion failed", error)
}
```

### Read (find) and the query builder

To perform the following query in MongoDB:

```json
{
	"username": "kitty"
}
```

Use the following MongoKitten code:

```swift
users.findOne("username" == "kitty").whenSuccess { (user: Document?) in
	// Do something with kitty
}
```

To perform the following query in MongoDB:

```json
{
	"$or": [
		{ "age": { "$lte": 16 } },
		{ "age": { "$exists": false } }
	]
}
```

Use the following MongoKitten code:

```swift
users.find("age" <= 16 || "age" == nil).forEach { (user: Document) in
	// Print the user's name
	print(user["username"] as? String)
}
```

You can also type out the queries yourself, without using the query builder, like this:

```swift
users.findOne(["username": "kitty"])
```

#### Cursors

Find operations return a `Cursor`. A cursor is a pointer to the result set of a query. You can obtain the results from a cursor by iterating over the results, or by fetching one or all of the results.

##### Fetching results

You can fetch all results as an array:

`let results: EventLoopFuture<[Document]> = users.find().getAllResults()`

Note that this is potentially dangerous with very large result sets. Only use `getAllResults()` when you are sure that the entire result set of your query fits comfortably in memory.

##### Iterating over results

For more efficient handling of results, you can lazily iterate over a cursor:

```swift
let doneIterating: EventLoopFuture<Void> = users.find().forEach { (user: Document) in
	// ...
}
```

##### Cursors are generic

Find operations return a `FindCursor<Document>`. As you can see, `FindCursor` is a generic type. You can lazily transform the cursor into a different result type by using `map`, which works similar to `map` on arrays or documents:

```swift
users.find()
	.map { document in
		return document["username"] as? String
	}
	.forEach { username: String? in
		print("user: \(username)")
	}
```

### Update

```swift
users.update(where: "username" == "kitty", setting: ["age": 3]).whenSuccess { _ in
	print("🐈")
}
```

### Delete

```swift
users.deleteOne(where: "username" == "kitty").whenSuccess { amountDeleted in
	print("Deleted \(amountDeleted) kitties 😿")
}
```

# 📦 About BSON & Documents

MongoDB is a document database that uses BSON under the hood to store JSON-like data. MongoKitten implements the [BSON specification](http://bsonspec.org) in its companion project, [OpenKitten/BSON](https://github.com/OpenKitten/BSON). You can find out more about our BSON implementation in the separate BSON repository, but here are the basics:

## Literals

You normally create BSON Documents like this:

```swift
let documentA: Document = ["_id": ObjectId(), "username": "kitty", "password": "meow"]
let documentB: Document = ["kitty", 4]
```

From the example above, we can learn a few things:

- A BSON document can represent an array *or* a dictionary
- You can initialize a document like you initialize normal dictionaries and arrays, using literals
- The values in a Document (either the array elements or the values of a dictionary pair) can be of any BSON primitive type
- BSON primitives include core Swift types like `Int`, `String`, `Double` and `Bool`, as well as `Date` from Foundation
- BSON also features some unique types, like `ObjectId`

## Just another collection

Like normal arrays and dictionaries, `Document` conforms to the `Collection` protocol. Because of this, you can often directly work with your `Document`, using the APIs you already know from `Array` and `Dictionary`. For example, you can iterate over a document using a for loop:

```swift
for (key, value) in documentA {
	// ...
}

for value in documentB.values {
	// ...
}
```

Document also provides subscripts to access individual elements. The subscripts return values of the type `Primitive?`, so you probably need to cast them using `as?` before using them.

```swift
let username = documentA["username"] as? String
```

### Think twice before converting between `Document` and `Dictionary`

Our `Document` type is implemented in an optimized, efficient way and provides many useful features to read and manipulate data, including features not present on the Swift `Dictionary` type. On top of that, `Document` also implements most APIs present on `Dictionary`, so there is very little learning curve.

# 💾 Codable

MongoKitten supports the `Encodable` and `Decodable` (`Codable`) protocols by providing the `BSONEncoder` and `BSONDecoder` types. Working with our encoders and decoders is very similar to working with the Foundation `JSONEncoder` and `JSONDecoder` classes, with the difference being that `BSONEncoder` produces instances of `Document` and `BSONDecoder` accepts instances of `Document`, instead of `Data`.

For example, say we want to code the following struct:

```swift
struct User: Codable {
	var profile: Profile?
	var username: String
	var password: String
	var age: Int?
	
	struct Profile: Codable {
		var profilePicture: Data?
		var firstName: String
		var lastName: String
	}
}
```

We can encode and decode instances like this:

```swift
let user: User = ...

let encoder = BSONEncoder()
let encoded: Document = try encoder.encode(user)

let decoder = BSONDecoder()
let decoded: User = try decoder.decode(User.self, from: encoded)
```

A few notes:

- `BSONEncoder` and `BSONDecoder` work very similar to other encoders and decoders
- Nested types can also be encoded and are encouraged
	- Nested structs and classes are most often encoded as embedded documents
- You can customize the representations using encoding/decoding strategies

## Codable and cursors

When doing a `find` query, the `Cursor`'s results can be transformed lazily. Lazy mapping is much more efficient than keeping the entire result set in memory as it allows for `forEach-` loops to be leveraged efficiently reducing the memory pressure of your application. You can leverage cursors using Codable as well.

```swift
// Find all and decode each Document lazily as a `User` type
users.find().decode(User.self).forEach { user in
	print(user.username)
}
```

# 🐈 Community

[Join our slack here](https://slackpass.io/openkitten) and become a part of the welcoming community.

# 🤝 How to help

## Support MongoKitten development

[We're accepting donations for our project here](https://opencollective.com/mongokitten). We hope to set up a good test environment as well as many docs, tutorials and examples.

### Backers

<a href="https://opencollective.com/mongokitten/backer/0/website" target="_blank"><img src="https://opencollective.com/mongokitten/backer/0/avatar.svg"></a>
<a href="twitter.com/DavidSights" target="_blank"><img src="https://opencollective.com/mongokitten/backer/1/avatar.svg"></a>


## Contribute to MongoKitten

- See [CONTRIBUTING.md](CONTRIBUTING.md) for info on contributing to MongoKitten
- You can help us out by resolving TODOs and replying on issues
- Of course, all feedback, positive and negative, also really helps to improve the project

# ☠️ License

MongoKitten is licensed under the MIT license.
