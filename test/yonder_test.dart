import 'package:built_collection/built_collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yonder/yonder.dart' as y;

void main() {
  test('Table can insert, update and delete', () {
    final table = y.Table<String, Plant>(
      keyFunction: (Plant plant) => plant.id,
    );

    final apple = Plant(id: '1', name: 'Apple', genus: 'Malus');
    final pear = Plant(id: '2', name: 'Pear', genus: 'Malus');

    expect(table.insert(apple), y.Optional.of('1'));
    expect(table.find('1'), apple);
    expect(table.lookup('1'), y.Optional.of(apple));
    expect(() => table.find('2'), throwsAssertionError);
    expect(table.lookup('2'), const y.Optional.absent());
    expect(table.insert(apple), const y.Optional.absent());
    expect(table.insert(pear), y.Optional.of('2'));
    expect(table.find('2'), pear);
    expect(table.removeByKey('3'), const y.Optional.absent());
    expect(table.removeByKey('2'), y.Optional.of(pear));
    expect(table.lookup('2'), const y.Optional.absent());
  });

  testWidgets('smoke test', (tester) async {
    await tester.pumpWidget(Text('Hi', textDirection: TextDirection.ltr));
  });
}

class PlantList extends StatefulWidget {
  PlantList({this.model});

  final Model model;

  @override
  State<StatefulWidget> createState() => PlantListState();
}

class PlantListState extends State<PlantList> {
  @override
  Widget build(BuildContext context) {
    setState(() {});
  }
}

class Model {
  Model() {
    _db = PlantDb();
    _notify();
  }

  void _notify() {
    plants.evaluate(_db);
  }

  PlantDb _db;
  set db(PlantDb value) {
    _db = value;
    _notify();
  }

  final plants = y.Query<PlantDb, BuiltList<Plant>>((db, previousValue) {
    return y.Optional.of(db.plants);
  });
}

class Plant {
  Plant({
    this.id,
    this.name,
    this.genus,
  });

  final String id;
  final String name;
  final String genus;

  @override
  int get hashCode => id.hashCode + 17 * (name.hashCode + 17 * genus.hashCode);

  @override
  operator ==(Object object) {
    if (object is! Plant) {
      return false;
    }

    Plant other = object;
    return other.id == id && other.name == name && other.genus == genus;
  }
}

class PlantDb {
  PlantDb({this.plants});

  final BuiltList<Plant> plants;
}
