import 'dart:collection';

import 'package:quiver/core.dart';
import 'package:quiver/collection.dart';
import 'package:flutter/widgets.dart';

export 'package:quiver/core.dart' show Optional;

typedef QueryEvaluator<M, V> = Optional<V> Function(
    M model, Optional<V> previousValue);
typedef QueryListener<V> = void Function(V value);

class Query<M, V> {
  Query(QueryEvaluator<M, V> evaluator)
      : assert(evaluator != null),
        _evaluator = evaluator;

  final QueryEvaluator<M, V> _evaluator;

  V get value => _value.value;
  Optional<V> _value = Optional.absent();

  void evaluate(M model) {
    if (_subscribers.isEmpty) {
      // Evaluation is done only for the purposes of notifying
      // subscribers about value changes. If there are no
      // subscribers, evaluation is skipped.
      return;
    }

    final evaluationResult = _evaluator(model, _value);

    if (!evaluationResult.isPresent) {
      // Value did not change.
      return;
    }

    _value = evaluationResult;

    for (QueryListener<V> subscriber in _subscribers) {
      subscriber(_value.value);
    }
  }

  final List<QueryListener<V>> _subscribers = <QueryListener<V>>[];

  QuerySubscription subscribe(QueryListener<V> listener) {
    _subscribers.add(listener);
    return QuerySubscription._(this, listener);
  }
}

class QuerySubscription {
  QuerySubscription._(this._query, this._listener);

  final Query _query;
  final QueryListener _listener;

  void unsubscribe() {
    _query._subscribers.remove(_listener);
  }
}

mixin QueryManager<T extends StatefulWidget> on State<T> {
  List<QuerySubscription> _subscriptions = <QuerySubscription>[];

  void query<M, V>(Query<M, V> q, QueryListener<V> listener) {
    _subscriptions.add(q.subscribe((V value) {
      setState(() {
        listener(value);
      });
    }));
    listener(q.value);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.unsubscribe();
    }
  }
}

typedef Computation<I, O> = O Function(I input);

class Table<K, V> {
  Table({@required this.keyFunction})
      : assert(keyFunction != null);

  final Computation<V, K> keyFunction;

  final HashMap<K, V> _data = HashMap<K, V>();
  final List<Index<K, V>> _indexes = <Index<K, V>>[];

  Optional<V> lookup(K key) {
    assert(key != null);
    if (!_data.containsKey(key)) {
      return const Optional.absent();
    }
    return Optional.fromNullable(_data[key]);
  }

  V find(K key) {
    assert(key != null);
    assert(_data.containsKey(key));
    return _data[key];
  }

  V operator [](K key) {
    assert(key != null);
    return find(key);
  }

  Optional<K> insert(V value) {
    assert(value != null);

    final K key = keyFunction(value);
    if(_data.containsKey(key)) {
      return const Optional.absent();
    }

    int i = 0;
    while (i < _indexes.length) {
      final Index<K, V> index = _indexes[i];
      if (!index.willInsert(key, value)) {
        break;
      }
      i++;
    }
    if (i < _indexes.length) {
      while (i >= 0) {
        final Index<K, V> index = _indexes[i];
        index.abandonPendingChange();
        i--;
      }
      return const Optional.absent();
    } else {
      _data[key] = value;
      for (final Index<K, V> index in _indexes) {
        index.commitPendingChange();
      }
      return Optional.of(key);
    }
  }

  Optional<K> update(V value) {
    assert(value != null);
    final K key = keyFunction(value);
    assert(_data.containsKey(key));
    if (_indexes.length == 0) {
      return Optional.of(key);
    }
    int i = 0;
    while (i < _indexes.length) {
      final Index<K, V> index = _indexes[i];
      if (!index.willUpdate(key, value)) {
        break;
      }
      i++;
    }
    if (i < _indexes.length) {
      while (i >= 0) {
        final Index<K, V> index = _indexes[i];
        index.abandonPendingChange();
        i--;
      }
      return const Optional.absent();
    } else {
      _data[key] = value;
      for (final Index<K, V> index in _indexes) {
        index.commitPendingChange();
      }
      return Optional.of(key);
    }
  }

  Optional<V> remove(V value) {
    assert(value != null);
    final K key = keyFunction(value);
    return removeByKey(key);
  }

  Optional<V> removeByKey(K key) {
    assert(key != null);
    if (!_data.containsKey(key)) {
      return const Optional.absent();
    }
    final V removedValue = _data[key];
    int i = 0;
    while (i < _indexes.length) {
      final Index<K, V> index = _indexes[i];
      if (!index.willRemove(key, removedValue)) {
        break;
      }
      i++;
    }
    if (i < _indexes.length) {
      while (i >= 0) {
        final Index<K, V> index = _indexes[i];
        index.abandonPendingChange();
        i--;
      }
      return const Optional.absent();
    } else {
      _data.remove(key);
      for (final Index<K, V> index in _indexes) {
        index.commitPendingChange();
      }
      return Optional.of(removedValue);
    }
  }
}

enum Write {
  insertion,
  update,
  removal,
}

abstract class Index<K, V> {
  Index(Table<K, V> table) : assert(table != null), this.table = table {
    table._indexes.add(this);
    initialize();
  }

  @protected
  final Table<K, V> table;

  @protected
  Write get pendingWrite => _pendingWrite;
  Write _pendingWrite;

  @protected
  K get pendingKey => _pendingKey;
  K _pendingKey;

  @protected
  V get pendingValue => _pendingValue;
  V _pendingValue;

  /// Indexes a table for the first time.
  void initialize() {
    table._data.forEach((K key, V value) {
      if (willInsert(key, value)) {
        commitPendingChange();
      }
    });
  }

  @protected
  @mustCallSuper
  bool willInsert(K key, V value) {
    _pendingWrite = Write.insertion;
    _pendingKey = key;
    _pendingValue = value;
    return true;
  }

  @protected
  @mustCallSuper
  bool willUpdate(K key, V value) {
    _pendingWrite = Write.update;
    _pendingKey = key;
    _pendingValue = value;
    return true;
  }

  @protected
  @mustCallSuper
  bool willRemove(K key, V value) {
    _pendingWrite = Write.removal;
    _pendingKey = key;
    _pendingValue = value;
    return true;
  }

  @protected
  @mustCallSuper
  void commitPendingChange() {
    _pendingWrite = null;
    _pendingKey = null;
    _pendingValue = null;
  }

  @protected
  @mustCallSuper
  void abandonPendingChange() {
    _pendingWrite = null;
    _pendingKey = null;
    _pendingValue = null;
  }
}

class Unique<K, V, U> extends Index<K, V> {
  Unique({
    @required Table<K, V> table,
    @required this.uniqueBy,
  }) : assert(uniqueBy != null), super(table);

  final Computation<V, U> uniqueBy;
  final HashBiMap<K, U> _index = HashBiMap<K, U>();

  U _pendingUniqueKey;

  @protected
  @mustCallSuper
  bool willInsert(K key, V value) {
    final U uniqueKey = uniqueBy(value);
    assert(uniqueKey != null);
    if (_index.containsValue(uniqueKey)) {
      // Another object with the same unique key exists in the index.
      return false;
    }
    return super.willInsert(key, value);
  }

  @protected
  @mustCallSuper
  bool willUpdate(K key, V value) {
    final U previousUniqueKey = _index[key];
    assert(previousUniqueKey != null);

    final U newUniqueKey = uniqueBy(value);
    assert(newUniqueKey != null);

    if (previousUniqueKey == newUniqueKey) {
      // Unique key didn't change. No re-index necessary.
      return true;
    } else {
      // Make sure there's no collisions.
      if (_index.containsValue(newUniqueKey)) {
        return false;
      }

      return super.willUpdate(key, value);
    }
  }

  @protected
  @mustCallSuper
  bool willRemove(K key, V value) {
    return super.willRemove(key, value);
  }

  @protected
  @mustCallSuper
  void commitPendingChange() {
    switch (pendingWrite) {
      case Write.insertion:
      case Write.update:
        _index[pendingKey] = _pendingUniqueKey;
        break;
      case Write.removal:
        _index.remove(pendingKey);
    }
    super.commitPendingChange();
  }

  @protected
  @mustCallSuper
  void abandonPendingChange() {
    _pendingUniqueKey = null;
    super.abandonPendingChange();
  }
}
