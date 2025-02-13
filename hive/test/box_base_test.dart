import 'dart:collection';

import 'package:hive/hive.dart';
import 'package:hive/src/backend/storage_backend.dart';
import 'package:hive/src/binary/frame.dart';
import 'package:hive/src/box/box_base.dart';
import 'package:hive/src/box/box_options.dart';
import 'package:hive/src/box/change_notifier.dart';
import 'package:hive/src/box/keystore.dart';
import 'package:hive/src/hive_impl.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'common.dart';

class BoxBaseMock extends BoxBase with Mock {
  BoxBaseMock({
    HiveImpl hive,
    String name,
    StorageBackend backend,
    Keystore keystore,
    ChangeNotifier notifier,
    CompactionStrategy cStrategy,
  }) : super(
          hive ?? HiveImpl(),
          name ?? 'testBox',
          BoxOptions(
            compactionStrategy: cStrategy ?? (total, deleted) => false,
          ),
          backend ?? BackendMock(),
          keystore ?? Keystore(),
          notifier ?? ChangeNotifier(),
        );
}

void main() {
  group('BoxBase', () {
    test('.name', () {
      var box = BoxBaseMock(name: 'testName');
      expect(box.name, 'testName');
    });

    test('.path', () {
      var backend = BackendMock();
      when(backend.path).thenReturn('some/path');
      var box = BoxBaseMock(backend: backend);
      expect(box.path, 'some/path');
    });

    test('.keys', () {
      var keystore = Keystore.debug([
        Frame('key1', null),
        Frame('key2', null),
        Frame('key4', null),
      ]);
      var box = BoxBaseMock(keystore: keystore);
      expect(HashSet.from(box.keys), HashSet.from(['key1', 'key2', 'key4']));
    });

    test('.length / .isEmpty / .isNotEmpty', () {
      var keystore = Keystore.debug([
        Frame('key1', null),
        Frame('key2', null),
      ]);
      var box = BoxBaseMock(keystore: keystore);
      expect(box.length, 2);
      expect(box.isEmpty, false);
      expect(box.isNotEmpty, true);

      keystore = Keystore();
      box = BoxBaseMock(keystore: keystore);
      expect(box.length, 0);
      expect(box.isEmpty, true);
      expect(box.isNotEmpty, false);
    });

    test('.watch()', () {
      var notifier = ChangeNotifierMock();
      var box = BoxBaseMock(notifier: notifier);
      box.watch(key: 123);
      verify(notifier.watch(key: 123));
    });

    test('.keyAt()', () {
      var keystore = Keystore.debug([Frame.lazy(0), Frame.lazy('test')]);
      var box = BoxBaseMock(keystore: keystore);
      expect(box.keyAt(1), 'test');
    });

    test('initialize', () async {
      var backend = BackendMock();
      var box = BoxBaseMock(backend: backend);

      when(backend.initialize(any, any, any, any)).thenAnswer((i) async {
        i.positionalArguments[1].add(Frame('key1', 1));
      });

      await box.initialize();
      expect(box.keystore.toValueMap(), {'key1': 1});
    });

    test('.containsKey()', () {
      var backend = BackendMock();
      var box = BoxBaseMock(
        backend: backend,
        keystore: Keystore.debug([Frame.lazy('existingKey')]),
      );

      expect(box.containsKey('existingKey'), true);
      expect(box.containsKey('nonExistingKey'), false);
      verifyZeroInteractions(backend);
    });

    test('add', () async {
      var keystore = Keystore();
      var box = BoxBaseMock(keystore: keystore);

      keystore.updateAutoIncrement(4);

      expect(await box.add(123), 5);
      verifyInOrder([
        keystore.autoIncrement(),
        box.put(5, 123),
      ]);
    });

    test('addAll', () async {
      var keystore = Keystore();
      var box = BoxBaseMock(keystore: keystore);

      keystore.updateAutoIncrement(4);

      expect(await box.addAll([1, 2, 3]), [5, 6, 7]);
      verifyInOrder([
        keystore.autoIncrement(),
        keystore.autoIncrement(),
        keystore.autoIncrement(),
        box.putAll({5: 1, 6: 2, 7: 3}),
      ]);
    });

    test('putAt', () async {
      var keystore = Keystore.debug([
        Frame.lazy('a'),
        Frame.lazy('b'),
        Frame.lazy('c'),
      ]);
      var box = BoxBaseMock(keystore: keystore);

      await box.putAt(1, 'test');
      verify(box.put('b', 'test'));
    });

    test('deleteAt', () async {
      var keystore = Keystore.debug([
        Frame.lazy('a'),
        Frame.lazy('b'),
        Frame.lazy('c'),
      ]);
      var box = BoxBaseMock(keystore: keystore);

      await box.deleteAt(1);
      verify(box.delete('b'));
    });

    test('.clear()', () async {
      var backend = BackendMock();
      var notifier = ChangeNotifierMock();
      var keystore = KeystoreMock();

      when(keystore.frames).thenReturn([
        Frame('key1', 123),
        Frame('key2', 345),
      ]);

      var box = BoxBaseMock(
        backend: backend,
        notifier: notifier,
        keystore: keystore,
      );

      expect(await box.clear(), 2);
      verifyInOrder([
        backend.clear(),
        keystore.frames,
        keystore.clear(),
        notifier.notify([Frame.deleted('key1'), Frame.deleted('key2')]),
      ]);
    });

    group('.compact()', () {
      test('does nothing if there are no deleted entries', () async {
        var backend = BackendMock();
        when(backend.supportsCompaction).thenReturn(true);
        var box = BoxBaseMock(
          backend: backend,
          keystore: Keystore.debug([Frame.lazy('key1')]),
        );
        await box.compact();
        verify(backend.supportsCompaction);
        verifyNoMoreInteractions(backend);
      });

      test('compact', () async {
        var backend = BackendMock();
        var keystore = KeystoreMock();

        when(keystore.frames)
            .thenReturn([Frame('key', 1, length: 22, offset: 33)]);
        when(backend.supportsCompaction).thenReturn(true);
        when(backend.compact(any)).thenAnswer((i) async {
          return [Frame('newKey', 2, length: 44, offset: 55)];
        });

        var box = BoxBaseMock(backend: backend, keystore: keystore);
        await box.compact();
        verifyInOrder([
          backend.supportsCompaction,
          keystore.deletedEntries,
          keystore.frames,
          backend.compact([Frame('key', 1, length: 22, offset: 33)]),
          keystore.resetDeletedEntries(),
        ]);
      });
    });

    test('.close()', () async {
      var hive = HiveMock();
      var notifier = ChangeNotifierMock();
      var backend = BackendMock();
      var box = BoxBaseMock(
        name: 'myBox',
        hive: hive,
        notifier: notifier,
        backend: backend,
      );

      await box.close();
      verifyInOrder([
        notifier.close(),
        hive.unregisterBox('myBox'),
        backend.close(),
      ]);
      expect(box.isOpen, false);
    });

    test('.deleteFromDisk()', () async {
      var hive = HiveMock();
      var notifier = ChangeNotifierMock();
      var backend = BackendMock();
      var box = BoxBaseMock(
        name: 'myBox',
        hive: hive,
        notifier: notifier,
        backend: backend,
      );

      await box.deleteFromDisk();
      verifyInOrder([
        notifier.close(),
        hive.unregisterBox('myBox'),
        backend.deleteFromDisk(),
      ]);
      expect(box.isOpen, false);
    });
  });
}
