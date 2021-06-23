/*
 * Copyright 2006-2007 Jeremias Maerki.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:typed_data';

import '../../common/detector/math_utils.dart';

import '../../dimension.dart';
import 'asciiencoder.dart';
import 'base256_encoder.dart';
import 'c40_encoder.dart';
import 'edifact_encoder.dart';
import 'encoder.dart';
import 'encoder_context.dart';
import 'symbol_shape_hint.dart';
import 'text_encoder.dart';
import 'x12_encoder.dart';

/// DataMatrix ECC 200 data encoder following the algorithm described in ISO/IEC 16022:200(E) in
/// annex S.
class HighLevelEncoder {
  /// Padding character
  static const int _PAD = 129;
  /// mode latch to C40 encodation mode
  static const int LATCH_TO_C40 = 230;
  /// mode latch to Base 256 encodation mode
  static const int LATCH_TO_BASE256 = 231;
  /// FNC1 Codeword
  //static const int _FNC1 = 232;
  /// Structured Append Codeword
  //static const int _STRUCTURED_APPEND = 233;
  /// Reader Programming
  //static const int _READER_PROGRAMMING = 234;
  /// Upper Shift chr
  static const int UPPER_SHIFT = 235;
  /// 05 Macro
  static const int _MACRO_05 = 236;
  /// 06 Macro
  static const int _MACRO_06 = 237;
  /// mode latch to ANSI X.12 encodation mode
  static const int LATCH_TO_ANSIX12 = 238;
  /// mode latch to Text encodation mode
  static const int LATCH_TO_TEXT = 239;
  /// mode latch to EDIFACT encodation mode
  static const int LATCH_TO_EDIFACT = 240;
  /// ECI character (Extended Channel Interpretation)
  //static const int _ECI = 241;

  /// Unlatch from C40 encodation
  static const int C40_UNLATCH = 254;
  /// Unlatch from X12 encodation
  static const int X12_UNLATCH = 254;

  /// 05 Macro header
  static const String _MACRO_05_HEADER = "[)>\u001E05\u001D";
  /// 06 Macro header
  static const String _MACRO_06_HEADER = "[)>\u001E06\u001D";
  /// Macro trailer
  static const String _MACRO_TRAILER = "\u001E\u0004";

  static const int ASCII_ENCODATION = 0;
  static const int C40_ENCODATION = 1;
  static const int TEXT_ENCODATION = 2;
  static const int X12_ENCODATION = 3;
  static const int EDIFACT_ENCODATION = 4;
  static const int BASE256_ENCODATION = 5;

  HighLevelEncoder._();

  static int _randomize253State(int codewordPosition) {
    int pseudoRandom = ((149 * codewordPosition) % 253) + 1;
    int tempVariable = _PAD + pseudoRandom;
    return tempVariable <= 254 ? tempVariable : tempVariable - 254;
  }

  /// Performs message encoding of a DataMatrix message using the algorithm described in annex P
  /// of ISO/IEC 16022:2000(E).
  ///
  /// @param msg     the message
  /// @param shape   requested shape. May be {@code SymbolShapeHint.FORCE_NONE},
  ///                {@code SymbolShapeHint.FORCE_SQUARE} or {@code SymbolShapeHint.FORCE_RECTANGLE}.
  /// @param minSize the minimum symbol size constraint or null for no constraint
  /// @param maxSize the maximum symbol size constraint or null for no constraint
  /// @return the encoded message (the char values range from 0 to 255)
  static String encodeHighLevel(String msg,
      [SymbolShapeHint shape = SymbolShapeHint.FORCE_NONE,
      Dimension? minSize,
      Dimension? maxSize]) {
    //the codewords 0..255 are encoded as Unicode characters
    List<Encoder> encoders = [
      ASCIIEncoder(),
      C40Encoder(),
      TextEncoder(),
      X12Encoder(),
      EdifactEncoder(),
      Base256Encoder()
    ];

    EncoderContext context = EncoderContext(msg);
    context.setSymbolShape(shape);
    context.setSizeConstraints(minSize, maxSize);

    if (msg.startsWith(_MACRO_05_HEADER) && msg.endsWith(_MACRO_TRAILER)) {
      context.writeCodeword(_MACRO_05);
      context.setSkipAtEnd(2);
      context.pos += _MACRO_05_HEADER.length;
    } else if (msg.startsWith(_MACRO_06_HEADER) && msg.endsWith(_MACRO_TRAILER)) {
      context.writeCodeword(_MACRO_06);
      context.setSkipAtEnd(2);
      context.pos += _MACRO_06_HEADER.length;
    }

    int encodingMode = ASCII_ENCODATION; //Default mode
    while (context.hasMoreCharacters) {
      encoders[encodingMode].encode(context);
      if (context.newEncoding >= 0) {
        encodingMode = context.newEncoding;
        context.resetEncoderSignal();
      }
    }
    int len = context.codewordCount;
    context.updateSymbolInfo();
    int capacity = context.symbolInfo!.dataCapacity;
    if (len < capacity &&
        encodingMode != ASCII_ENCODATION &&
        encodingMode != BASE256_ENCODATION &&
        encodingMode != EDIFACT_ENCODATION) {
      context.writeCodeword('\u00fe'); //Unlatch (254)
    }
    //Padding
    StringBuffer codewords = context.codewords;
    if (codewords.length < capacity) {
      codewords.writeCharCode(_PAD);
    }
    while (codewords.length < capacity) {
      codewords.writeCharCode(_randomize253State(codewords.length + 1));
    }

    return context.codewords.toString();
  }

  static int lookAheadTest(String msg, int startPos, int currentMode) {
    if (startPos >= msg.length) {
      return currentMode;
    }
    List<double> charCounts;
    //step J
    if (currentMode == ASCII_ENCODATION) {
      charCounts = [0, 1, 1, 1, 1, 1.25];
    } else {
      charCounts = [1, 2, 2, 2, 2, 2.25];
      charCounts[currentMode] = 0;
    }

    int charsProcessed = 0;
    while (true) {
      //step K
      if ((startPos + charsProcessed) == msg.length) {
        int min = MathUtils.MAX_VALUE;
        Int8List mins = Int8List(6);
        Int32List intCharCounts = Int32List(6);
        min = _findMinimums(charCounts, intCharCounts, min, mins);
        int minCount = _getMinimumCount(mins);

        if (intCharCounts[ASCII_ENCODATION] == min) {
          return ASCII_ENCODATION;
        }
        if (minCount == 1 && mins[BASE256_ENCODATION] > 0) {
          return BASE256_ENCODATION;
        }
        if (minCount == 1 && mins[EDIFACT_ENCODATION] > 0) {
          return EDIFACT_ENCODATION;
        }
        if (minCount == 1 && mins[TEXT_ENCODATION] > 0) {
          return TEXT_ENCODATION;
        }
        if (minCount == 1 && mins[X12_ENCODATION] > 0) {
          return X12_ENCODATION;
        }
        return C40_ENCODATION;
      }

      int c = msg.codeUnitAt(startPos + charsProcessed);
      charsProcessed++;

      //step L
      if (isDigit(c)) {
        charCounts[ASCII_ENCODATION] += 0.5;
      } else if (isExtendedASCII(c)) {
        charCounts[ASCII_ENCODATION] =
            (charCounts[ASCII_ENCODATION]).ceil().toDouble();
        charCounts[ASCII_ENCODATION] += 2.0;
      } else {
        charCounts[ASCII_ENCODATION] =
            (charCounts[ASCII_ENCODATION]).ceil().toDouble();
        charCounts[ASCII_ENCODATION]++;
      }

      //step M
      if (_isNativeC40(c)) {
        charCounts[C40_ENCODATION] += 2.0 / 3.0;
      } else if (isExtendedASCII(c)) {
        charCounts[C40_ENCODATION] += 8.0 / 3.0;
      } else {
        charCounts[C40_ENCODATION] += 4.0 / 3.0;
      }

      //step N
      if (_isNativeText(c)) {
        charCounts[TEXT_ENCODATION] += 2.0 / 3.0;
      } else if (isExtendedASCII(c)) {
        charCounts[TEXT_ENCODATION] += 8.0 / 3.0;
      } else {
        charCounts[TEXT_ENCODATION] += 4.0 / 3.0;
      }

      //step O
      if (_isNativeX12(c)) {
        charCounts[X12_ENCODATION] += 2.0 / 3.0;
      } else if (isExtendedASCII(c)) {
        charCounts[X12_ENCODATION] += 13.0 / 3.0;
      } else {
        charCounts[X12_ENCODATION] += 10.0 / 3.0;
      }

      //step P
      if (_isNativeEDIFACT(c)) {
        charCounts[EDIFACT_ENCODATION] += 3.0 / 4.0;
      } else if (isExtendedASCII(c)) {
        charCounts[EDIFACT_ENCODATION] += 17.0 / 4.0;
      } else {
        charCounts[EDIFACT_ENCODATION] += 13.0 / 4.0;
      }

      // step Q
      if (_isSpecialB256(c)) {
        charCounts[BASE256_ENCODATION] += 4.0;
      } else {
        charCounts[BASE256_ENCODATION]++;
      }

      //step R
      if (charsProcessed >= 4) {
        List<int> intCharCounts = Int32List(6);
        Int8List mins = Int8List(6);
        _findMinimums(charCounts, intCharCounts, MathUtils.MAX_VALUE, mins); // int.MAX
        int minCount = _getMinimumCount(mins);

        if (intCharCounts[ASCII_ENCODATION] <
                intCharCounts[BASE256_ENCODATION] &&
            intCharCounts[ASCII_ENCODATION] < intCharCounts[C40_ENCODATION] &&
            intCharCounts[ASCII_ENCODATION] < intCharCounts[TEXT_ENCODATION] &&
            intCharCounts[ASCII_ENCODATION] < intCharCounts[X12_ENCODATION] &&
            intCharCounts[ASCII_ENCODATION] <
                intCharCounts[EDIFACT_ENCODATION]) {
          return ASCII_ENCODATION;
        }
        if (intCharCounts[BASE256_ENCODATION] <
                intCharCounts[ASCII_ENCODATION] ||
            (mins[C40_ENCODATION] +
                    mins[TEXT_ENCODATION] +
                    mins[X12_ENCODATION] +
                    mins[EDIFACT_ENCODATION]) ==
                0) {
          return BASE256_ENCODATION;
        }
        if (minCount == 1 && mins[EDIFACT_ENCODATION] > 0) {
          return EDIFACT_ENCODATION;
        }
        if (minCount == 1 && mins[TEXT_ENCODATION] > 0) {
          return TEXT_ENCODATION;
        }
        if (minCount == 1 && mins[X12_ENCODATION] > 0) {
          return X12_ENCODATION;
        }
        if (intCharCounts[C40_ENCODATION] + 1 <
                intCharCounts[ASCII_ENCODATION] &&
            intCharCounts[C40_ENCODATION] + 1 <
                intCharCounts[BASE256_ENCODATION] &&
            intCharCounts[C40_ENCODATION] + 1 <
                intCharCounts[EDIFACT_ENCODATION] &&
            intCharCounts[C40_ENCODATION] + 1 <
                intCharCounts[TEXT_ENCODATION]) {
          if (intCharCounts[C40_ENCODATION] < intCharCounts[X12_ENCODATION]) {
            return C40_ENCODATION;
          }
          if (intCharCounts[C40_ENCODATION] == intCharCounts[X12_ENCODATION]) {
            int p = startPos + charsProcessed + 1;
            while (p < msg.length) {
              int tc = msg.codeUnitAt(p);
              if (_isX12TermSep(tc)) {
                return X12_ENCODATION;
              }
              if (!_isNativeX12(tc)) {
                break;
              }
              p++;
            }
            return C40_ENCODATION;
          }
        }
      }
    }
  }

  static int _findMinimums(List<double> charCounts, List<int> intCharCounts,
      int min, Int8List mins) {
    mins.fillRange(0, mins.length, 0);
    for (int i = 0; i < 6; i++) {
      intCharCounts[i] = (charCounts[i]).ceil();
      int current = intCharCounts[i];
      if (min > current) {
        min = current;
        mins.fillRange(0, mins.length, 0);
      }
      if (min == current) {
        mins[i]++;
      }
    }
    return min;
  }

  static int _getMinimumCount(Int8List mins) {
    int minCount = 0;
    for (int i = 0; i < 6; i++) {
      minCount += mins[i];
    }
    return minCount;
  }

  static bool isDigit(dynamic chr) {
    int ch = 0;
    if (chr is String)
      ch = chr.codeUnitAt(0);
    else
      ch = chr as int;
    return ch >= 48 /* 0 */ && ch <= 57 /* 9 */;
  }

  static bool isExtendedASCII(dynamic chr) {
    int ch = 0;
    if (chr is String)
      ch = chr.codeUnitAt(0);
    else
      ch = chr as int;
    return ch >= 128 && ch <= 255;
  }

  static bool _isNativeC40(dynamic chr) {
    int ch = 0;
    if (chr is String)
      ch = chr.codeUnitAt(0);
    else
      ch = chr as int;
    return (ch == 32 /*   */) ||
        (ch >= 48 /* 0 */ && ch <= 57 /* 9 */) ||
        (ch >= 65 /* A */ && ch <= 90 /* Z */);
  }

  static bool _isNativeText(dynamic chr) {
    int ch = 0;
    if (chr is String)
      ch = chr.codeUnitAt(0);
    else
      ch = chr as int;
    return (ch == 32 /*   */) ||
        (ch >= 48 /* 0 */ && ch <= 57 /* 9 */) ||
        (ch >= 97 /* a */ && ch <= 122 /* z */);
  }

  static bool _isNativeX12(dynamic chr) {
    int ch = 0;
    if (chr is String)
      ch = chr.codeUnitAt(0);
    else
      ch = chr as int;
    return _isX12TermSep(ch) ||
        (ch == 32 /*   */) ||
        (ch >= 48 /* 0 */ && ch <= 57 /* 9 */) ||
        (ch >= 65 /* A */ && ch <= 90 /* Z */);
  }

  static bool _isX12TermSep(dynamic chr) {
    int ch = 0;
    if (chr is String)
      ch = chr.codeUnitAt(0);
    else
      ch = chr as int;
    return (ch == 13) //CR
        ||
        (ch == 42 /* * */) ||
        (ch == 62 /* > */);
  }

  static bool _isNativeEDIFACT(dynamic chr) {
    int ch = 0;
    if (chr is String)
      ch = chr.codeUnitAt(0);
    else
      ch = chr as int;
    return ch >= 32 /*   */ && ch <= 94 /* ^ */;
  }

  static bool _isSpecialB256(dynamic chr) {
    return false; //TODO NOT IMPLEMENTED YET!!!
  }

  /// Determines the number of consecutive characters that are encodable using numeric compaction.
  ///
  /// @param msg      the message
  /// @param startPos the start position within the message
  /// @return the requested character count
  static int determineConsecutiveDigitCount(String msg, int startPos) {
    int count = 0;
    int len = msg.length;
    int idx = startPos;
    if (idx < len) {
      int ch = msg.codeUnitAt(idx);
      while (isDigit(ch) && idx < len) {
        count++;
        idx++;
        if (idx < len) {
          ch = msg.codeUnitAt(idx);
        }
      }
    }
    return count;
  }

  static void illegalCharacter(int c) {
    String hex = (c).toRadixString(16);
    hex = "0000".substring(0, 4 - hex.length) + hex;
    throw Exception(
        "Illegal character: chr($c) (0x$hex)");
  }
}