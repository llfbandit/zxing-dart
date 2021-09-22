/*
 * Copyright (C) 2010 ZXing authors
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

/*
 * These authors would like to acknowledge the Spanish Ministry of Industry,
 * Tourism and Trade, for the support in the project TSI020301-2008-2
 * "PIRAmIDE: Personalizable Interactions with Resources on AmI-enabled
 * Mobile Dynamic Environments", led by Treelogic
 * ( http://www.treelogic.com/ ):
 *
 *   http://www.piramidepse.com/
 */

import '../data_character.dart';
import '../finder_pattern.dart';

/// @author Pablo Orduña, University of Deusto (pablo.orduna@deusto.es)
class ExpandedPair {
  final DataCharacter? _leftChar;
  final DataCharacter? _rightChar;
  final FinderPattern? _finderPattern;

  ExpandedPair(this._leftChar, this._rightChar, this._finderPattern);

  DataCharacter? get leftChar => _leftChar;

  DataCharacter? get rightChar => _rightChar;

  FinderPattern? get finderPattern => _finderPattern;

  bool get mustBeLast => _rightChar == null;

  @override
  String toString() {
    return "[ $_leftChar , $_rightChar : ${_finderPattern == null ? "null" : _finderPattern!.value} ]";
  }

  @override
  operator ==(Object other) {
    if (other is! ExpandedPair) {
      return false;
    }
    return (_leftChar == other._leftChar) &&
        (_rightChar == other._rightChar) &&
        (_finderPattern == other._finderPattern);
  }

  @override
  int get hashCode {
    return _leftChar.hashCode ^ _rightChar.hashCode ^ _finderPattern.hashCode;
  }
}
