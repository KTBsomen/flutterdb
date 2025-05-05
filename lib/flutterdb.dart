library flutterdb;

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'dart:math';

/// Generates unique IDs for documents
class IdGenerator {
  static String generateId() {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/
            1000) // use seconds like MongoDB
        .toRadixString(16)
        .padLeft(8, '0');
    final randomPart = _getRandomPart();
    final counter = _getCounter();
    return '$timestamp$randomPart$counter';
  }

  static String _getRandomPart() {
    final rand = Random();
    List<int> randomBytes = List.generate(5, (_) => rand.nextInt(256));
    return randomBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _getCounter() {
    return Random()
        .nextInt(0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0'); // 3 bytes
  }
}

/// Main database class that manages collections
class FlutterDB {
  static final FlutterDB _instance = FlutterDB._internal();
  static Database? _database;
  static const int _version = 1;

  factory FlutterDB() {
    return _instance;
  }

  FlutterDB._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory directory = await getApplicationDocumentsDirectory();
    String dbPath = path.join(directory.path, 'flutterdb.db');
    return await openDatabase(
      dbPath,
      version: _version,
      onCreate: _createDb,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE collections (
        name TEXT PRIMARY KEY
      )
    ''');

    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        collection_name TEXT,
        data TEXT,
        created_at INTEGER,
        updated_at INTEGER,
        FOREIGN KEY (collection_name) REFERENCES collections (name) ON DELETE CASCADE
      )
    ''');

    // Create indexes for faster querying
    await db
        .execute('CREATE INDEX idx_collection ON documents (collection_name)');
    await db.execute('PRAGMA journal_mode=WAL;');
  }

  /// Creates a collection if it doesn't exist
  Future<Collection> collection(String name) async {
    final db = await database;

    // Check if collection exists
    final collections = await db.query(
      'collections',
      where: 'name = ?',
      whereArgs: [name],
    );

    // If collection doesn't exist, create it
    if (collections.isEmpty) {
      await db.insert('collections', {'name': name});
    }

    return Collection(name, db);
  }

  /// Drops a collection
  Future<bool> dropCollection(String name) async {
    final db = await database;
    try {
      await db.delete(
        'collections',
        where: 'name = ?',
        whereArgs: [name],
      );
      await db.delete(
        'documents',
        where: 'collection_name = ?',
        whereArgs: [name],
      );
      return true;
    } catch (e) {
      print('Error dropping collection: $e');
      return false;
    }
  }

  /// Lists all collections
  Future<List<String>> listCollections() async {
    final db = await database;
    final collections = await db.query('collections');
    return collections.map((c) => c['name'] as String).toList();
  }
}

/// Gets a nested value from a document using dot notation
dynamic _getNestedValue(Map<String, dynamic> doc, String field) {
  final parts = field.split('.');
  dynamic value = doc;

  for (var part in parts) {
    if (value is Map<String, dynamic>) {
      value = value[part];
    } else {
      return null;
    }
  }

  return value;
}

/// Represents a collection in the database
class Collection {
  final String name;
  final Database _db;

  Collection(this.name, this._db);

  /// Inserts a document into the collection
  Future<String> insert(Map<String, dynamic> document) async {
    final id = document['_id'] ?? IdGenerator.generateId();
    document['_id'] = id;

    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.insert('documents', {
      'id': id,
      'collection_name': name,
      'data': jsonEncode(document),
      'created_at': now,
      'updated_at': now,
    });

    return id;
  }

  /// Inserts multiple documents into the collection
  Future<List<String>> insertMany(List<Map<String, dynamic>> documents) async {
    final ids = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (var document in documents) {
        final id = document['_id'] ?? IdGenerator.generateId();
        document['_id'] = id;
        ids.add(id);

        batch.insert('documents', {
          'id': id,
          'collection_name': name,
          'data': jsonEncode(document),
          'created_at': now,
          'updated_at': now,
        });
      }
      await batch.commit(noResult: true);
    });

    return ids;
  }

  /// Finds documents matching the query
  Future<List<Map<String, dynamic>>> find(Map<String, dynamic> query) async {
    // First get all documents in the collection
    final results = await _db.query(
      'documents',
      where: 'collection_name = ?',
      whereArgs: [name],
    );

    if (query.isEmpty) {
      // If no query, return all documents
      return results
          .map((doc) =>
              jsonDecode(doc['data'] as String) as Map<String, dynamic>)
          .toList();
    }

    // Filter documents based on query
    final filteredResults = results.where((doc) {
      final document =
          jsonDecode(doc['data'] as String) as Map<String, dynamic>;
      return _matchesQuery(document, query);
    }).toList();

    return filteredResults
        .map((doc) => jsonDecode(doc['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  /// Finds a single document by ID
  Future<Map<String, dynamic>?> findById(String id) async {
    final results = await _db.query(
      'documents',
      where: 'id = ? AND collection_name = ?',
      whereArgs: [id, name],
    );

    if (results.isEmpty) return null;
    return jsonDecode(results.first['data'] as String) as Map<String, dynamic>;
  }

  /// Updates a document by ID
  Future<bool> updateById(String id, Map<String, dynamic> update) async {
    // First get the document
    final doc = await findById(id);
    if (doc == null) return false;

    // Merge the update with the existing document
    doc.addAll(update);
    doc['_id'] = id; // Ensure ID is preserved

    // Update the document
    final now = DateTime.now().millisecondsSinceEpoch;
    final count = await _db.update(
      'documents',
      {
        'data': jsonEncode(doc),
        'updated_at': now,
      },
      where: 'id = ? AND collection_name = ?',
      whereArgs: [id, name],
    );

    return count > 0;
  }

  /// Updates documents matching the query
  Future<int> updateMany(
      Map<String, dynamic> query, Map<String, dynamic> update) async {
    // First find all matching documents
    final docs = await find(query);
    if (docs.isEmpty) return 0;

    final batch = _db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (var doc in docs) {
      final id = doc['_id'] as String;
      doc.addAll(update);
      doc['_id'] = id; // Ensure ID is preserved

      batch.update(
        'documents',
        {
          'data': jsonEncode(doc),
          'updated_at': now,
        },
        where: 'id = ? AND collection_name = ?',
        whereArgs: [id, name],
      );
    }

    await batch.commit(noResult: true);
    return docs.length;
  }

  /// Deletes a document by ID
  Future<bool> deleteById(String id) async {
    final count = await _db.delete(
      'documents',
      where: 'id = ? AND collection_name = ?',
      whereArgs: [id, name],
    );

    return count > 0;
  }

  /// Deletes documents matching the query
  Future<int> deleteMany(Map<String, dynamic> query) async {
    // First find all matching documents
    final docs = await find(query);
    if (docs.isEmpty) return 0;

    final batch = _db.batch();

    for (var doc in docs) {
      final id = doc['_id'] as String;
      batch.delete(
        'documents',
        where: 'id = ? AND collection_name = ?',
        whereArgs: [id, name],
      );
    }

    await batch.commit(noResult: true);
    return docs.length;
  }

  /// Counts documents matching the query
  Future<int> count([Map<String, dynamic>? query]) async {
    if (query == null || query.isEmpty) {
      final result = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM documents WHERE collection_name = ?',
        [name],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }

    // If there's a query, we need to find matching documents first
    final docs = await find(query);
    return docs.length;
  }

  /// Performs aggregation operations
  Future<List<Map<String, dynamic>>> aggregate(
      List<Map<String, dynamic>> pipeline) async {
    List<Map<String, dynamic>> results = await find({});

    for (var stage in pipeline) {
      if (stage.containsKey('\$match')) {
        final matchQuery = stage['\$match'] as Map<String, dynamic>;
        results =
            results.where((doc) => _matchesQuery(doc, matchQuery)).toList();
      } else if (stage.containsKey('\$sort')) {
        final sortFields = stage['\$sort'] as Map<String, dynamic>;
        results.sort((a, b) {
          for (var field in sortFields.keys) {
            final direction = sortFields[field] as int;
            final valueA = _getNestedValue(a, field);
            final valueB = _getNestedValue(b, field);

            int comparison;
            if (valueA == null && valueB == null) {
              comparison = 0;
            } else if (valueA == null) {
              comparison = -1;
            } else if (valueB == null) {
              comparison = 1;
            } else if (valueA is Comparable && valueB is Comparable) {
              comparison = valueA.compareTo(valueB);
            } else {
              comparison = 0;
            }

            if (comparison != 0) {
              return direction * comparison;
            }
          }
          return 0;
        });
      } else if (stage.containsKey('\$limit')) {
        final limit = stage['\$limit'] as int;
        results = results.take(limit).toList();
      } else if (stage.containsKey('\$skip')) {
        final skip = stage['\$skip'] as int;
        if (skip < results.length) {
          results = results.sublist(skip);
        } else {
          results = [];
        }
      } else if (stage.containsKey('\$group')) {
        final groupSpec = stage['\$group'] as Map<String, dynamic>;
        final idExpr = groupSpec['_id'];
        final Map<dynamic, Map<String, dynamic>> grouped = {};

        for (var doc in results) {
          // Support simple grouping by field (e.g., { _id: '$city' })
          dynamic groupKey;
          if (idExpr is String && idExpr.startsWith(r'$')) {
            final field = idExpr.substring(1); // Remove the leading $
            groupKey = _getNestedValue(doc, field);
          } else {
            groupKey = idExpr;
          }

          // Initialize group if not already present
          grouped.putIfAbsent(groupKey, () {
            final newGroup = <String, dynamic>{'_id': groupKey};
            groupSpec.forEach((key, value) {
              if (key != '_id') {
                if (value is Map && value.containsKey('\$sum')) {
                  newGroup[key] = 0; // initialize sum to 0
                }
                if (value is Map && value.containsKey('\$avg')) {
                  newGroup[key] = 0; // initialize avg to 0
                }
                if (value is Map && value.containsKey('\$max')) {
                  newGroup[key] =
                      double.negativeInfinity; // initialize max to -inf
                }
                if (value is Map && value.containsKey('\$min')) {
                  newGroup[key] = double.infinity; // initialize min to inf
                }
                if (value is Map && value.containsKey('\$push')) {
                  newGroup[key] = []; // initialize push to empty list
                }
                if (value is Map && value.containsKey('\$addToSet')) {
                  newGroup[key] =
                      <dynamic>{}; // initialize addToSet to empty set
                }
                if (value is Map && value.containsKey('\$first')) {
                  newGroup[key] = null; // initialize first to null
                }
                if (value is Map && value.containsKey('\$last')) {
                  newGroup[key] = null; // initialize last to null
                }
                if (value is Map && value.containsKey('\$stdDevPop')) {
                  newGroup[key] = 0; // initialize stdDevPop to 0
                }
                if (value is Map && value.containsKey('\$stdDevSamp')) {
                  newGroup[key] = 0; // initialize stdDevSamp to 0
                }
                if (value is Map && value.containsKey('\$mergeObjects')) {
                  newGroup[key] = {}; // initialize mergeObjects to empty map
                }
                if (value is Map && value.containsKey('\$concatArrays')) {
                  newGroup[key] = []; // initialize concatArrays to empty list
                }
                if (value is Map && value.containsKey('\$arrayToObject')) {
                  newGroup[key] = {}; // initialize arrayToObject to empty map
                }
                if (value is Map && value.containsKey('\$reduce')) {
                  newGroup[key] = null; // initialize reduce to null
                }
                if (value is Map && value.containsKey('\$setUnion')) {
                  newGroup[key] =
                      <dynamic>[]; // initialize setUnion to empty list
                }
                if (value is Map && value.containsKey('\$setIntersection')) {
                  newGroup[key] =
                      <dynamic>[]; // initialize setIntersection to empty list
                }
                if (value is Map && value.containsKey('\$setDifference')) {
                  newGroup[key] =
                      <dynamic>[]; // initialize setDifference to empty list
                }
                if (value is Map && value.containsKey('\$setIsSubset')) {
                  newGroup[key] =
                      <dynamic>[]; // initialize setIsSubset to empty list
                }
                if (value is Map && value.containsKey('\$setEquals')) {
                  newGroup[key] =
                      <dynamic>[]; // initialize setEquals to empty list
                }

                // You can initialize other accumulators here
                // e.g., $avg, $max, etc.
              }
            });
            return newGroup;
          });

          // Apply accumulators
          groupSpec.forEach((key, value) {
            if (key == '_id') return; // skip _id

            if (value is Map && value.containsKey('\$sum')) {
              final sumField = value['\$sum'];
              num toAdd = 0;
              if (sumField is num) {
                toAdd = sumField;
              } else if (sumField is String && sumField.startsWith(r'$')) {
                final field = sumField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                if (fieldValue is num) {
                  toAdd = fieldValue;
                }
              }
              grouped[groupKey]![key] += toAdd;
            }
            if (value is Map && value.containsKey('\$avg')) {
              final avgField = value['\$avg'];
              num toAdd = 0;
              if (avgField is num) {
                toAdd = avgField;
              } else if (avgField is String && avgField.startsWith(r'$')) {
                final field = avgField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                if (fieldValue is num) {
                  toAdd = fieldValue;
                }
              }
              grouped[groupKey]![key] += toAdd; // Update average
            }
            if (value is Map && value.containsKey('\$max')) {
              final maxField = value['\$max'];
              num toAdd = double.negativeInfinity;
              if (maxField is num) {
                toAdd = maxField;
              } else if (maxField is String && maxField.startsWith(r'$')) {
                final field = maxField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                if (fieldValue is num) {
                  toAdd = fieldValue;
                }
              }
              grouped[groupKey]![key] =
                  max(grouped[groupKey]![key] as num, toAdd); // Update max
            }
            if (value is Map && value.containsKey('\$min')) {
              final minField = value['\$min'];
              num toAdd = double.infinity;
              if (minField is num) {
                toAdd = minField;
              } else if (minField is String && minField.startsWith(r'$')) {
                final field = minField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                if (fieldValue is num) {
                  toAdd = fieldValue;
                }
              }
              grouped[groupKey]![key] =
                  min(grouped[groupKey]![key] as num, toAdd); // Update min
            }
            if (value is Map && value.containsKey('\$push')) {
              final pushField = value['\$push'];
              if (pushField is String && pushField.startsWith(r'$')) {
                final field = pushField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].add(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$addToSet')) {
              final addToSetField = value['\$addToSet'];
              if (addToSetField is String && addToSetField.startsWith(r'$')) {
                final field =
                    addToSetField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].add(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$first')) {
              final firstField = value['\$first'];
              if (firstField is String && firstField.startsWith(r'$')) {
                final field = firstField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key] = fieldValue;
              }
            }
            if (value is Map && value.containsKey('\$last')) {
              final lastField = value['\$last'];
              if (lastField is String && lastField.startsWith(r'$')) {
                final field = lastField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key] = fieldValue;
              }
            }
            if (value is Map && value.containsKey('\$stdDevPop')) {
              final stdDevPopField = value['\$stdDevPop'];
              num toAdd = 0;
              if (stdDevPopField is num) {
                toAdd = stdDevPopField;
              } else if (stdDevPopField is String &&
                  stdDevPopField.startsWith(r'$')) {
                final field =
                    stdDevPopField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                if (fieldValue is num) {
                  toAdd = fieldValue;
                }
              }
              grouped[groupKey]![key] += toAdd; // Update stdDevPop
            }
            if (value is Map && value.containsKey('\$stdDevSamp')) {
              final stdDevSampField = value['\$stdDevSamp'];
              num toAdd = 0;
              if (stdDevSampField is num) {
                toAdd = stdDevSampField;
              } else if (stdDevSampField is String &&
                  stdDevSampField.startsWith(r'$')) {
                final field =
                    stdDevSampField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                if (fieldValue is num) {
                  toAdd = fieldValue;
                }
              }
              grouped[groupKey]![key] += toAdd; // Update stdDevSamp
            }
            if (value is Map && value.containsKey('\$mergeObjects')) {
              final mergeObjectsField = value['\$mergeObjects'];
              if (mergeObjectsField is String &&
                  mergeObjectsField.startsWith(r'$')) {
                final field =
                    mergeObjectsField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].addAll(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$concatArrays')) {
              final concatArraysField = value['\$concatArrays'];
              if (concatArraysField is String &&
                  concatArraysField.startsWith(r'$')) {
                final field =
                    concatArraysField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].addAll(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$arrayToObject')) {
              final arrayToObjectField = value['\$arrayToObject'];
              if (arrayToObjectField is String &&
                  arrayToObjectField.startsWith(r'$')) {
                final field =
                    arrayToObjectField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].addAll(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$reduce')) {
              final reduceField = value['\$reduce'];
              if (reduceField is String && reduceField.startsWith(r'$')) {
                final field = reduceField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].addAll(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$setUnion')) {
              final setUnionField = value['\$setUnion'];
              if (setUnionField is String && setUnionField.startsWith(r'$')) {
                final field =
                    setUnionField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].addAll(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$setIntersection')) {
              final setIntersectionField = value['\$setIntersection'];
              if (setIntersectionField is String &&
                  setIntersectionField.startsWith(r'$')) {
                final field =
                    setIntersectionField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].addAll(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$setDifference')) {
              final setDifferenceField = value['\$setDifference'];
              if (setDifferenceField is String &&
                  setDifferenceField.startsWith(r'$')) {
                final field =
                    setDifferenceField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].addAll(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$setIsSubset')) {
              final setIsSubsetField = value['\$setIsSubset'];
              if (setIsSubsetField is String &&
                  setIsSubsetField.startsWith(r'$')) {
                final field =
                    setIsSubsetField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].addAll(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$setEquals')) {
              final setEqualsField = value['\$setEquals'];
              if (setEqualsField is String && setEqualsField.startsWith(r'$')) {
                final field =
                    setEqualsField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].addAll(fieldValue);
              }
            }
            if (value is Map && value.containsKey('\$setIsSubset')) {
              final setIsSubsetField = value['\$setIsSubset'];
              if (setIsSubsetField is String &&
                  setIsSubsetField.startsWith(r'$')) {
                final field =
                    setIsSubsetField.substring(1); // Remove the leading $
                final fieldValue = _getNestedValue(doc, field);
                grouped[groupKey]![key].addAll(fieldValue);
              }
            }

            // Add other accumulators (like $avg, $max) here as needed
          });
        }

        results = grouped.values.toList();
      } else if (stage.containsKey('\$count')) {
        final countField = stage['\$count'] as String;
        results = [
          {countField: results.length}
        ];
      } else if (stage.containsKey('\$project')) {
        final projectFields = stage['\$project'] as Map<String, dynamic>;
        results = results.map((doc) {
          final projectedDoc = <String, dynamic>{};
          projectFields.forEach((key, value) {
            if (value == 1) {
              projectedDoc[key] = doc[key];
            } else if (value == 0) {
              projectedDoc.remove(key);
            }
          });
          return projectedDoc;
        }).toList();
      } else if (stage.containsKey('\$unwind')) {
        final unwindField = stage['\$unwind'] as String;
        final unwindResults = <Map<String, dynamic>>[];

        for (var doc in results) {
          final unwindValue = _getNestedValue(doc, unwindField);
          if (unwindValue is List) {
            for (var item in unwindValue) {
              final newDoc = Map<String, dynamic>.from(doc);
              newDoc[unwindField] = item;
              unwindResults.add(newDoc);
            }
          } else {
            unwindResults.add(doc);
          }
        }

        results = unwindResults;
      } else if (stage.containsKey('\$lookup')) {
        // Handle $lookup stage here if needed
        final lookupStage = stage['\$lookup'] as Map<String, dynamic>;
        final from = lookupStage['from'] as String;
        final localField = lookupStage['localField'] as String;
        final foreignField = lookupStage['foreignField'] as String;
        final as = lookupStage['as'] as String;
        final foreignCollection = await FlutterDB().collection(from);
        final foreignDocs = await foreignCollection.find({});
        final lookupResults = <Map<String, dynamic>>[];
        for (var doc in results) {
          final localValue = _getNestedValue(doc, localField);
          final matchingForeignDocs = foreignDocs.where((foreignDoc) {
            final foreignValue = _getNestedValue(foreignDoc, foreignField);
            return localValue == foreignValue;
          }).toList();
          final newDoc = Map<String, dynamic>.from(doc);
          newDoc[as] = matchingForeignDocs;
          lookupResults.add(newDoc);
        }
        results = lookupResults;
      } else if (stage.containsKey('\$geoNear')) {
        // Handle $geoNear stage here if needed
        final geoNearStage = stage['\$geoNear'] as Map<String, dynamic>;
        final near = geoNearStage['near'] as List<double>;
        final distanceField = geoNearStage['distanceField'] as String;
        final spherical = geoNearStage['spherical'] as bool? ?? false;
        final maxDistance = geoNearStage['maxDistance'] as double?;
        final resultsWithDistance = <Map<String, dynamic>>[];

        for (var doc in results) {
          final location = _getNestedValue(doc, distanceField) as List<double>?;
          if (location != null) {
            final distance = sqrt(
                pow(location[0] - near[0], 2) + pow(location[1] - near[1], 2));
            if (maxDistance == null || distance <= maxDistance) {
              final newDoc = Map<String, dynamic>.from(doc);
              newDoc[distanceField] = distance;
              resultsWithDistance.add(newDoc);
            }
          }
        }

        results = resultsWithDistance;
      }
      // Add more stages if needed
    }
    return results;
  }

  /// Matches a document against a query
  bool _matchesQuery(
      Map<String, dynamic> document, Map<String, dynamic> query) {
    for (var key in query.keys) {
      var queryValue = query[key];

      if (key.startsWith('\$')) {
        // Handle top-level operators
        switch (key) {
          case '\$or':
            if (queryValue is! List) return false;
            bool orMatches = false;
            for (var subQuery in queryValue) {
              if (_matchesQuery(document, subQuery)) {
                orMatches = true;
                break;
              }
            }
            if (!orMatches) return false;
            break;
          case '\$and':
            if (queryValue is! List) return false;
            for (var subQuery in queryValue) {
              if (!_matchesQuery(document, subQuery)) {
                return false;
              }
            }
            break;
          case '\$nor':
            if (queryValue is! List) return false;
            for (var subQuery in queryValue) {
              if (_matchesQuery(document, subQuery)) {
                return false;
              }
            }
            break;
          default:
            return false;
        }
      } else if (queryValue is Map<String, dynamic>) {
        // Handle field operators
        var docValue = _getNestedValue(document, key);

        for (var op in queryValue.keys) {
          var expectedValue = queryValue[op];

          switch (op) {
            case '\$eq':
              if (docValue != expectedValue) return false;
              break;
            case '\$gt':
              if (docValue is num && expectedValue is num) {
                if (!(docValue > expectedValue)) return false;
              } else if (docValue is String && expectedValue is String) {
                if (!(docValue.compareTo(expectedValue) > 0)) return false;
              } else {
                return false;
              }
              break;
            case '\$gte':
              if (docValue is num && expectedValue is num) {
                if (!(docValue >= expectedValue)) return false;
              } else if (docValue is String && expectedValue is String) {
                if (!(docValue.compareTo(expectedValue) >= 0)) return false;
              } else {
                return false;
              }
              break;
            case '\$lt':
              if (docValue is num && expectedValue is num) {
                if (!(docValue < expectedValue)) return false;
              } else if (docValue is String && expectedValue is String) {
                if (!(docValue.compareTo(expectedValue) < 0)) return false;
              } else {
                return false;
              }
              break;
            case '\$lte':
              if (docValue is num && expectedValue is num) {
                if (!(docValue <= expectedValue)) return false;
              } else if (docValue is String && expectedValue is String) {
                if (!(docValue.compareTo(expectedValue) <= 0)) return false;
              } else {
                return false;
              }
              break;
            case '\$ne':
              if (docValue == expectedValue) return false;
              break;
            case '\$in':
              if (!(expectedValue is List && expectedValue.contains(docValue)))
                return false;
              break;
            case '\$nin':
              if (!(expectedValue is List && !expectedValue.contains(docValue)))
                return false;
              break;
            case '\$exists':
              final exists = document.containsKey(key) || docValue != null;
              if (expectedValue is bool && exists != expectedValue)
                return false;
              break;
            case '\$regex':
              if (!(docValue is String && expectedValue is String))
                return false;
              try {
                final regex = RegExp(expectedValue);
                if (!regex.hasMatch(docValue)) return false;
              } catch (e) {
                return false;
              }
              break;
            case '\$like':
              if (!(docValue is String &&
                  expectedValue is String &&
                  docValue.contains(expectedValue))) return false;
              break;
            default:
              return false;
          }
        }
      } else {
        // Simple equality match
        final docValue = _getNestedValue(document, key);
        if (docValue != queryValue) return false;
      }
    }

    return true;
  }
}
