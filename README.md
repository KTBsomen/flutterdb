# FlutterDB

FlutterDB is a lightweight, SQLite-based document database for Flutter applications. It provides a MongoDB-like API for managing collections and documents while leveraging the performance benefits of SQLite.

## Features

- Document-oriented database with collections and documents
- MongoDB-style query syntax and operations
- Built on top of SQLite for performance and reliability
- Unique ID generation for documents
- Support for complex queries, updates, and aggregations
- Batch operations for better performance

## Installation

Add the following dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  flutterdb: ^0.0.2
```

## Getting Started

Import the package:

```dart
import 'package:flutterdb/flutterdb.dart';
```

Initialize the database:

```dart
final db = FlutterDB();
```

## Basic Usage

### Working with Collections

```dart
// Create or get a collection
final users = await db.collection('users');

// List all collections
final collections = await db.listCollections();

// Drop a collection
await db.dropCollection('users');
```

### CRUD Operations

#### Create

```dart
// Insert a single document
final userId = await users.insert({
  'name': 'John Doe',
  'email': 'john@example.com',
  'age': 30
});

// Insert multiple documents
final ids = await users.insertMany([
  {
    'name': 'Jane Smith',
    'email': 'jane@example.com',
    'age': 25
  },
  {
    'name': 'Bob Johnson',
    'email': 'bob@example.com',
    'age': 40
  }
]);
```

#### Read

```dart
// Find all documents in a collection
final allUsers = await users.find({});

// Find documents with a simple query
final adults = await users.find({'age': {'\$gte': 18}});

// Find a document by ID
final user = await users.findById(userId);
// Find by page
final users = await users.findByPage(page: 1, limit: 10);

// Count documents
final userCount = await users.count({'age': {'\$gt': 30}});
```

#### Update

```dart
// Update a document by ID
await users.updateById(userId, {'status': 'active'});

// Update multiple documents
final updatedCount = await users.updateMany(
  {'age': {'\$lt': 30}},
  {'status': 'young'}
);
```

#### Delete

```dart
// Delete a document by ID
await users.deleteById(userId);

// Delete multiple documents
final deletedCount = await users.deleteMany({'status': 'inactive'});
```

## Advanced Queries

### Comparison Operators

```dart
// Greater than
await users.find({'age': {'\$gt': 30}});

// Less than or equal
await users.find({'age': {'\$lte': 25}});

// Not equal
await users.find({'status': {'\$ne': 'inactive'}});

// In array
await users.find({'role': {'\$in': ['admin', 'moderator']}});
```

### Logical Operators

```dart
// AND
await users.find({
  '\$and': [
    {'age': {'\$gte': 18}},
    {'status': 'active'}
  ]
});

// OR
await users.find({
  '\$or': [
    {'role': 'admin'},
    {'permissions': {'\$in': ['write', 'delete']}}
  ]
});

// NOR
await users.find({
  '\$nor': [
    {'status': 'banned'},
    {'role': 'guest'}
  ]
});
```

### Text Search

```dart
// Regex search
await users.find({'name': {'\$regex': '^Jo'}});

// Simple text search
await users.find({'bio': {'\$like': 'flutter developer'}});
```

### Aggregation

```dart
final results = await users.aggregate([
  {'\$match': {'status': 'active'}},
  {'\$sort': {'age': -1}},
  {'\$skip': 10},
  {'\$limit': 20},
  {'\$project': {
          'name': 1,
          'age': 1,
          'city': 1,
          '_id': 0,
               }
  },
  {'\$group': {
          '_id': '\$city',
          'count': {'\$sum': 1}
        }
  },
]);
```

## Best Practices

### Performance Optimization

1. **Use batch operations** for multiple insertions or updates:
   ```dart
   await users.insertMany(manyUsers); // Better than inserting one by one
   ```

2. **Keep document size reasonable**:
   - Large documents can slow down performance
   - Consider storing large binary data (images, files) separately

3. **Create indexes** for frequently queried fields:
   - Currently, FlutterDB automatically indexes collection names
   - Future versions may support custom indexes

4. **Use appropriate queries**:
   - Finding by ID is faster than complex queries
   - Limit results when possible using `\$limit`

### Data Structure

1. **Use consistent schemas**:
   - While FlutterDB is schemaless, consistent document structures improve code maintainability

2. **Choose good document IDs**:
   - Let FlutterDB generate IDs unless you have specific requirements
   - Custom IDs should be unique and consistent

3. **Handle relationships thoughtfully**:
   - For one-to-many relationships, consider embedding related data or using references

### Error Handling

Always implement error handling:

```dart
try {
  await users.insert({'name': 'John'});
} catch (e) {
  print('Error inserting document: $e');
  // Handle error appropriately
}
```

## Limitations

1. **Not a full MongoDB replacement**:
   - Limited subset of MongoDB query operators
   - Some complex aggregation operations not supported

2. **Performance with large datasets**:
   - Best suited for mobile apps with moderate data size
   - Consider pagination or limiting queries for large collections

3. **No built-in encryption**:
   - Data is stored in plain text
   - Consider additional encryption for sensitive data

4. **Limited indexing options**:
   - Custom indexes not yet supported
   - Consider query performance for large collections

5. **No network synchronization**:
   - Local database only
   - Implement your own sync solution if needed

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:flutterdb/flutterdb.dart';

class UserRepository {
  final FlutterDB _db = FlutterDB();
  late Future<Collection> _users;

  UserRepository() {
    _users = _db.collection('users');
  }

  Future<String> addUser(String name, String email, int age) async {
    final collection = await _users;
    return await collection.insert({
      'name': name,
      'email': email,
      'age': age,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAdultUsers() async {
    final collection = await _users;
    return await collection.find({
      'age': {'\$gte': 18},
    });
  }

  Future<void> updateUserStatus(String id, String status) async {
    final collection = await _users;
    await collection.updateById(id, {
      'status': status,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final userRepo = UserRepository();
  
  // Add a user
  final userId = await userRepo.addUser('Alice', 'alice@example.com', 28);
  print('Added user with ID: $userId');
  
  // Update user status
  await userRepo.updateUserStatus(userId, 'premium');
  
  // Get all adult users
  final adults = await userRepo.getAdultUsers();
  for (var user in adults) {
    print('User: ${user['name']}, Age: ${user['age']}, Status: ${user['status']}');
  }
}
```

## Future Enhancements

- Custom indexing support
- More aggregation pipeline operators
- Full-text search capabilities
- Data encryption options
- Schema validation
- Observable queries
- Migration support

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the GNU AGPLv3 License - see the LICENSE file for details.