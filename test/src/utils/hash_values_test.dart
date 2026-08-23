import 'package:test/test.dart';
import 'package:xterm/src/utils/hash_values.dart';

void main() {
  group('hashValues', () {
    test('is deterministic for the same inputs', () {
      expect(hashValues(1, 'two'), hashValues(1, 'two'));
    });

    test('is sensitive to argument order', () {
      expect(hashValues(1, 2), isNot(hashValues(2, 1)));
    });

    test('is sensitive to argument count', () {
      expect(hashValues(1, 2), isNot(hashValues(1, 2, 3)));
    });

    test('distinguishes null from a value', () {
      expect(hashValues(null, null), isNot(hashValues(null, 1)));
      expect(hashValues(1, null), isNot(hashValues(1, 1)));
    });

    test('handles null arguments deterministically', () {
      expect(hashValues(null, null), hashValues(null, null));
    });

    test('agrees with hashList for two arguments', () {
      expect(hashValues(1, 2), hashList([1, 2]));
    });

    test('agrees with hashList for many arguments', () {
      expect(
        hashValues('a', 1, true, 2.5, 'b'),
        hashList(['a', 1, true, 2.5, 'b']),
      );
    });

    test('uses all 20 argument slots', () {
      final nineteen =
          hashValues(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, null);
      final twenty =
          hashValues(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20);
      expect(nineteen, isNot(twenty));
      expect(twenty, hashList(List<int>.generate(20, (i) => i + 1)));
    });

    test('passing an Iterable as an argument violates the assert', () {
      // hashValues documents that iterables must go through hashList instead;
      // in debug mode this trips the assert in _Jenkins.combine.
      expect(() => hashValues(1, [2]), throwsA(isA<AssertionError>()));
    });
  });

  group('hashList', () {
    test('is deterministic for the same inputs', () {
      expect(hashList([1, 2, 3]), hashList([1, 2, 3]));
    });

    test('is sensitive to element order', () {
      expect(hashList([1, 2, 3]), isNot(hashList([3, 2, 1])));
    });

    test('empty list hashes to zero', () {
      expect(hashList([]), 0);
      expect(hashList([]), hashList(<Object>[]));
    });

    test('empty list collides with a list containing a single zero', () {
      // Documents a quirk of the Jenkins combine: combining 0 onto a zero
      // seed is a no-op, so [] and [0] produce the same hash.
      expect(hashList([]), hashList([0]));
      expect(hashList([]), isNot(hashList([1])));
    });

    test('single element list is deterministic', () {
      expect(hashList([42]), hashList([42]));
      expect(hashList([42]), isNot(hashList([43])));
    });
  });
}
