import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutterdb/flutterdb.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DatabasePerformanceTestApp());
}

class DatabasePerformanceTestApp extends StatelessWidget {
  const DatabasePerformanceTestApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DB Performance Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PerformanceTestScreen(),
    );
  }
}

class PerformanceTestScreen extends StatefulWidget {
  const PerformanceTestScreen({Key? key}) : super(key: key);

  @override
  State<PerformanceTestScreen> createState() => _PerformanceTestScreenState();
}

class _PerformanceTestScreenState extends State<PerformanceTestScreen> {
  final FlutterDB _db = FlutterDB();
  final TextEditingController _documentCountController =
      TextEditingController(text: "1000");
  final ScrollController _scrollController = ScrollController();
  final List<String> _logs = [];

  bool _isRunning = false;
  int _progress = 0;
  int _totalOperations = 0;

  // Test results
  Map<String, int> _insertionTimes = {};
  Map<String, int> _queryTimes = {};
  Map<String, int> _updateTimes = {};
  Map<String, int> _deleteTimes = {};

  @override
  void dispose() {
    _documentCountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _log(String message) {
    setState(() {
      _logs.add("${DateTime.now().toString().split('.').first}: $message");

      // Scroll to bottom after rendering
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  Future<void> _runPerformanceTest() async {
    if (_isRunning) return;

    // Reset state
    setState(() {
      _isRunning = true;
      _progress = 0;
      _logs.clear();
      _insertionTimes = {};
      _queryTimes = {};
      _updateTimes = {};
      _deleteTimes = {};
    });

    int documentCount;
    try {
      documentCount = int.parse(_documentCountController.text);
      if (documentCount <= 0) throw Exception();
    } catch (e) {
      _log("Please enter a valid number of documents");
      setState(() => _isRunning = false);
      return;
    }

    _log("Starting performance test with $documentCount documents");
    _totalOperations = documentCount * 4; // insert, query, update, delete

    try {
      // Clean up any previous test data
      _log("Cleaning up previous test data...");
      await _db.dropCollection("performance_test");

      // Get the collection
      final collection = await _db.collection("performance_test");

      // TEST 1: INSERTION PERFORMANCE
      _log("TEST 1: Testing single insertion performance...");
      await _testSingleInsertions(collection, documentCount ~/ 10);

      _log("TEST 2: Testing batch insertion performance...");
      await _testBatchInsertions(
          collection, documentCount - (documentCount ~/ 10));

      // TEST 3: QUERY PERFORMANCE
      _log("TEST 3: Testing query performance...");
      await _testQueries(collection, documentCount);

      // TEST 4: UPDATE PERFORMANCE
      _log("TEST 4: Testing update performance...");
      await _testUpdates(collection, documentCount);

      // TEST 5: DELETE PERFORMANCE
      _log("TEST 5: Testing deletion performance...");
      await _testDeletions(collection, documentCount);

      // TEST 6: Complex query performance
      _log("TEST 6: Testing complex query performance...");
      await _testComplexQueries(collection);

      // Print summary
      _logPerformanceSummary();
    } catch (e) {
      _log("Error during performance test: $e");
    } finally {
      // Clean up test data
      await _db.dropCollection("performance_test");
      setState(() => _isRunning = false);
      _log("Test completed and test data cleaned up");
    }
  }

  Future<void> _testSingleInsertions(Collection collection, int count) async {
    final Stopwatch stopwatch = Stopwatch()..start();

    for (int i = 0; i < count; i++) {
      await collection.insert(_generateDocument(i));
      _incrementProgress();

      if (i % 100 == 0 || i == count - 1) {
        _log("Inserted ${i + 1} documents");
      }
    }

    stopwatch.stop();
    _insertionTimes['single'] = stopwatch.elapsedMilliseconds;
    _log(
        "Single insertion test completed in ${stopwatch.elapsedMilliseconds}ms");
    _log(
        "Average time per document: ${stopwatch.elapsedMilliseconds / count}ms");
  }

  Future<void> _testBatchInsertions(Collection collection, int count) async {
    final Stopwatch stopwatch = Stopwatch()..start();

    // Insert in batches of 100
    final batchSize = 100;
    for (int i = 0; i < count; i += batchSize) {
      final batchCount = min(batchSize, count - i);
      final documents = List.generate(
          batchCount,
          (index) => _generateDocument(
              index + i + 1000) // offset to avoid ID conflicts
          );

      await collection.insertMany(documents);

      for (int j = 0; j < batchCount; j++) {
        _incrementProgress();
      }

      _log(
          "Inserted batch of $batchCount documents (total: ${i + batchCount})");
    }

    stopwatch.stop();
    _insertionTimes['batch'] = stopwatch.elapsedMilliseconds;
    _log(
        "Batch insertion test completed in ${stopwatch.elapsedMilliseconds}ms");
    _log(
        "Average time per document: ${stopwatch.elapsedMilliseconds / count}ms");
  }

  Future<void> _testQueries(Collection collection, int count) async {
    // Simple queries
    final Stopwatch simpleStopwatch = Stopwatch()..start();

    // Query by field equals
    int equalsQueryTime =
        await _runTimedQuery(collection, "Simple equals query", {"age": 30});

    // Query by range
    int rangeQueryTime = await _runTimedQuery(collection, "Range query", {
      "age": {"\$gt": 20, "\$lt": 40}
    });

    // Query with OR
    int orQueryTime = await _runTimedQuery(collection, "OR query", {
      "\$or": [
        {
          "age": {"\$lt": 20}
        },
        {
          "name": {"\$like": "User 5"}
        }
      ]
    });

    simpleStopwatch.stop();
    _queryTimes['simple'] = simpleStopwatch.elapsedMilliseconds;
    _queryTimes['equals'] = equalsQueryTime;
    _queryTimes['range'] = rangeQueryTime;
    _queryTimes['or'] = orQueryTime;

    _log("Query tests completed in ${simpleStopwatch.elapsedMilliseconds}ms");

    // Update progress counter
    for (int i = 0; i < count; i++) {
      _incrementProgress();
    }
  }

  Future<int> _runTimedQuery(Collection collection, String queryName,
      Map<String, dynamic> query) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final results = await collection.find(query);
    stopwatch.stop();

    _log(
        "$queryName returned ${results.length} results in ${stopwatch.elapsedMilliseconds}ms");
    return stopwatch.elapsedMilliseconds;
  }

  Future<void> _testUpdates(Collection collection, int count) async {
    final Stopwatch stopwatch = Stopwatch()..start();

    // Get all documents
    final allDocs = await collection.find({});

    // Update each document individually
    for (int i = 0; i < min(count, allDocs.length); i++) {
      final doc = allDocs[i];
      await collection.updateById(doc['_id'], {
        'updated': true,
        'updateTimestamp': DateTime.now().millisecondsSinceEpoch
      });

      _incrementProgress();

      if (i % 100 == 0 || i == allDocs.length - 1) {
        _log("Updated ${i + 1} documents");
      }
    }

    stopwatch.stop();
    _updateTimes['individual'] = stopwatch.elapsedMilliseconds;
    _log("Update test completed in ${stopwatch.elapsedMilliseconds}ms");
    _log(
        "Average time per update: ${stopwatch.elapsedMilliseconds / min(count, allDocs.length)}ms");
  }

  Future<void> _testDeletions(Collection collection, int count) async {
    final Stopwatch stopwatch = Stopwatch()..start();

    // Get all documents
    final allDocs = await collection.find({});

    // Delete each document individually
    for (int i = 0; i < min(count, allDocs.length); i++) {
      final doc = allDocs[i];
      await collection.deleteById(doc['_id']);

      _incrementProgress();

      if (i % 100 == 0 || i == allDocs.length - 1) {
        _log("Deleted ${i + 1} documents");
      }
    }

    stopwatch.stop();
    _deleteTimes['individual'] = stopwatch.elapsedMilliseconds;
    _log("Deletion test completed in ${stopwatch.elapsedMilliseconds}ms");
    _log(
        "Average time per deletion: ${stopwatch.elapsedMilliseconds / min(count, allDocs.length)}ms");
  }

  Future<void> _testComplexQueries(Collection collection) async {
    // First insert some test data with varied attributes
    _log("Inserting data for complex query testing...");
    await collection.insertMany([
      {
        "name": "User A",
        "age": 25,
        "tags": ["developer", "flutter"],
        "active": true,
        "score": 85
      },
      {
        "name": "User B",
        "age": 32,
        "tags": ["manager", "dart"],
        "active": true,
        "score": 72
      },
      {
        "name": "User C",
        "age": 19,
        "tags": ["student", "flutter"],
        "active": false,
        "score": 95
      },
      {
        "name": "User D",
        "age": 40,
        "tags": ["developer", "senior"],
        "active": true,
        "score": 88
      },
      {
        "name": "User E",
        "age": 27,
        "tags": ["developer", "junior"],
        "active": true,
        "score": 65
      },
    ]);

    // Test complex query 1: AND with nested conditions
    await _runTimedQuery(
        collection, "Complex query - AND with nested conditions", {
      "age": {"\$gt": 20},
      "tags": {
        "\$in": ["developer"]
      },
      "active": true
    });

    // Test complex query 2: OR with multiple conditions
    await _runTimedQuery(
        collection, "Complex query - OR with multiple conditions", {
      "\$or": [
        {
          "age": {"\$lt": 20}
        },
        {
          "score": {"\$gt": 80}
        }
      ]
    });

    // Test complex query 3: Mixed AND/OR
    await _runTimedQuery(collection, "Complex query - Mixed AND/OR", {
      "active": true,
      "\$or": [
        {
          "age": {"\$lt": 30}
        },
        {
          "score": {"\$gt": 80}
        }
      ]
    });

    // Test aggregation
    final Stopwatch aggregationStopwatch = Stopwatch()..start();
    final aggregationResult = await collection.aggregate([
      {
        "\$match": {"active": true}
      },
      {
        "\$sort": {"score": -1}
      }
    ]);
    aggregationStopwatch.stop();

    _queryTimes['aggregation'] = aggregationStopwatch.elapsedMilliseconds;
    _log(
        "Aggregation completed in ${aggregationStopwatch.elapsedMilliseconds}ms with ${aggregationResult.length} results");
  }

  void _incrementProgress() {
    setState(() {
      _progress++;
    });
  }

  void _logPerformanceSummary() {
    _log("\n===== PERFORMANCE SUMMARY =====");
    _log("INSERTION:");
    _log("  • Single inserts: ${_insertionTimes['single']}ms");
    _log("  • Batch inserts: ${_insertionTimes['batch']}ms");

    _log("\nQUERIES:");
    _log("  • Simple equals query: ${_queryTimes['equals']}ms");
    _log("  • Range query: ${_queryTimes['range']}ms");
    _log("  • OR query: ${_queryTimes['or']}ms");
    _log("  • Aggregation: ${_queryTimes['aggregation']}ms");

    _log("\nUPDATES:");
    _log("  • Individual updates: ${_updateTimes['individual']}ms");

    _log("\nDELETIONS:");
    _log("  • Individual deletions: ${_deleteTimes['individual']}ms");
  }

  Map<String, dynamic> _generateDocument(int index) {
    final random = Random();
    return {
      "name": "User $index",
      "age": 18 + random.nextInt(50),
      "email": "user$index@example.com",
      "isActive": random.nextBool(),
      "registeredAt": DateTime.now()
          .subtract(Duration(days: random.nextInt(365)))
          .millisecondsSinceEpoch,
      "score": random.nextDouble() * 100,
      "tags": _getRandomTags(random),
      "address": {
        "city": _getRandomCity(random),
        "zipCode": 10000 + random.nextInt(90000),
      }
    };
  }

  List<String> _getRandomTags(Random random) {
    final allTags = [
      "developer",
      "designer",
      "manager",
      "student",
      "senior",
      "junior",
      "flutter",
      "dart",
      "mobile"
    ];
    final numTags = 1 + random.nextInt(3); // 1-3 tags
    final selectedTags = <String>[];

    for (int i = 0; i < numTags; i++) {
      final tag = allTags[random.nextInt(allTags.length)];
      if (!selectedTags.contains(tag)) {
        selectedTags.add(tag);
      }
    }

    return selectedTags;
  }

  String _getRandomCity(Random random) {
    final cities = [
      "New York",
      "London",
      "Tokyo",
      "Paris",
      "Berlin",
      "Sydney",
      "Mumbai",
      "Cairo",
      "Rio"
    ];
    return cities[random.nextInt(cities.length)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Performance Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Database Performance Test',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _documentCountController,
                    decoration: const InputDecoration(
                      labelText: 'Number of documents',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !_isRunning,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _isRunning ? null : _runPerformanceTest,
                  child: const Text('Run Test'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isRunning)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Progress:'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value:
                        _totalOperations > 0 ? _progress / _totalOperations : 0,
                  ),
                  const SizedBox(height: 4),
                  Text('$_progress / $_totalOperations operations completed'),
                ],
              ),
            const SizedBox(height: 16),
            const Text(
              'Test Log:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        log,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              log.contains("===== PERFORMANCE SUMMARY =====")
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                          color: log.contains("Error")
                              ? Colors.red
                              : log.contains("===== PERFORMANCE SUMMARY =====")
                                  ? Colors.blue
                                  : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ComparisonScreen extends StatelessWidget {
  final Map<String, int> oldDbTimes;
  final Map<String, int> newDbTimes;

  const ComparisonScreen({
    Key? key,
    required this.oldDbTimes,
    required this.newDbTimes,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Comparison'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Old DB vs New DB Performance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  _buildComparisonSection(
                      'Single Insert', 'single', 'insertion'),
                  _buildComparisonSection('Batch Insert', 'batch', 'insertion'),
                  _buildComparisonSection(
                      'Simple Equals Query', 'equals', 'query'),
                  _buildComparisonSection('Range Query', 'range', 'query'),
                  _buildComparisonSection('OR Query', 'or', 'query'),
                  _buildComparisonSection('Updates', 'individual', 'update'),
                  _buildComparisonSection('Deletions', 'individual', 'delete'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonSection(String title, String key, String category) {
    // Access times based on category and key
    final oldTime = _getTime(oldDbTimes, key, category);
    final newTime = _getTime(newDbTimes, key, category);

    // Calculate improvement percentage
    final improvement = oldTime > 0 ? ((oldTime - newTime) / oldTime * 100) : 0;
    final isImproved = newTime < oldTime;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Old DB:'),
                      Text(
                        '${oldTime}ms',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('New DB:'),
                      Text(
                        '${newTime}ms',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isImproved
                  ? '${improvement.toStringAsFixed(1)}% faster'
                  : '${(-improvement).toStringAsFixed(1)}% slower',
              style: TextStyle(
                color: isImproved ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _getTime(Map<String, int> times, String key, String category) {
    if (category == 'insertion') {
      return times['${key}'] ?? 0;
    } else if (category == 'query') {
      return times['${key}'] ?? 0;
    } else if (category == 'update') {
      return times['${key}'] ?? 0;
    } else if (category == 'delete') {
      return times['${key}'] ?? 0;
    }
    return 0;
  }
}
