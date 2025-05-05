import 'package:flutter/material.dart';
import 'package:flutterdb/flutterdb.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late FlutterDB db;
  Collection? users;
  String log = '';

  @override
  void initState() {
    super.initState();
    initDB();
  }

  Future<void> initDB() async {
    db = FlutterDB();
    users = await db.collection('users');
    setState(() {
      log += 'DB Initialized\n';
    });
  }

  Future<void> insertSampleData() async {
    await users?.insertMany([
      {'name': 'Alice', 'age': 25, 'city': 'New York'},
      {'name': 'Bob', 'age': 30, 'city': 'Los Angeles'},
      {'name': 'Charlie', 'age': 35, 'city': 'New York'},
      {'name': 'Diana', 'age': 28, 'city': 'Chicago'},
    ]);
    setState(() {
      log += 'Inserted sample data\n';
    });
  }

  getAllusers() async {
    final results = await users?.aggregate([
      // {
      //   '\$match': {
      //     'age': {'\$lt': 26}
      //   }
      // },
      {
        '\$sort': {'_id': 1}
      },
      {'\$limit': 10},
      {
        '\$project': {
          'name': 1,
          'age': 1,
          'city': 1,
          '_id': 0,
        }
      },
    ]);
    print('All Users: $results');
    setState(() {
      log += 'All Users: ${results?.map((e) => e['name']).toList()}\n';
    });
  }

  Future<void> runFindQuery() async {
    final results = await users?.find({
      'age': {'\$gt': 26}
    });
    print('Results: $results');
    setState(() {
      log += 'Find >26: ${results?.map((e) => e['name']).toList()}\n';
    });
  }

  Future<void> runFindOneQuery() async {
    final result = await users?.find({
      '_id': {'\$lt': "6818931ba3a814141211166d"},
      // 'age': {'\$te': 26}
    });
    print('Results: $result');
  }

  Future<void> runUpdate() async {
    final updated = await users?.updateMany(
      {'city': 'New York'},
      {'status': 'NY Resident'},
    );
    setState(() {
      log += 'Updated ${updated} users in New York\n';
    });
  }

  Future<void> runAggregation() async {
    final results = await users?.aggregate([
      {
        '\$group': {
          '_id': '\$city',
          'count': {'\$sum': 1}
        }
      },
    ]);
    setState(() {
      log += 'Aggregation (count by city): $results\n';
    });
  }

  Future<void> runComplexQuery() async {
    final results = await users?.find({
      '\$or': [
        {
          'age': {'\$lt': 28}
        },
        {
          'status': {'\$exists': true}
        },
      ]
    });
    setState(() {
      log +=
          'Complex query result: ${results?.map((e) => e['name']).toList()}\n';
    });
  }

  Future<void> clearDB() async {
    await db.dropCollection('users');
    setState(() {
      log += 'Database cleared\n';
      log = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterDB Demo',
      home: Scaffold(
        appBar: AppBar(title: Text('FlutterDB Demo')),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                      onPressed: getAllusers, child: Text('Get All Users')),
                  ElevatedButton(
                      onPressed: insertSampleData, child: Text('Insert')),
                  ElevatedButton(
                      onPressed: runFindQuery, child: Text('Find >26')),
                  ElevatedButton(
                      onPressed: runFindOneQuery, child: Text('find less _id')),
                  ElevatedButton(
                      onPressed: runUpdate, child: Text('Update NY')),
                  ElevatedButton(
                      onPressed: runAggregation, child: Text('Aggregate')),
                  ElevatedButton(
                      onPressed: runComplexQuery, child: Text('Complex Query')),
                  ElevatedButton(onPressed: clearDB, child: Text('Clear DB')),
                ],
              ),
              SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(log, style: TextStyle(fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
