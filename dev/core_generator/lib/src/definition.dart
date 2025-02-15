import 'dart:convert';
import 'dart:io';

import 'package:colorize/colorize.dart';
// import 'package:core_generator/src/field_type.dart';
import 'package:core_generator/src/comment.dart';
import 'package:core_generator/src/field_type.dart';
import 'package:core_generator/src/key.dart';
import 'package:core_generator/src/cpp_formatter.dart';
import 'package:core_generator/src/property.dart';
import 'package:core_generator/src/configuration.dart';

String stripExtension(String filename) {
  var index = filename.lastIndexOf('.');
  return index == -1 ? filename : filename.substring(0, index);
}

class Definition {
  static final Map<String, Definition> definitions = <String, Definition>{};
  final String _filename;
  static final _formatter = CppFormatter();

  String _name;
  final List<Property> _properties = [];

  List<Property> get properties => _properties
      .where((property) => property.isRuntime)
      .toList(growable: false);

  Definition _extensionOf;
  Key _key;
  bool _isAbstract = false;
  bool _editorOnly = false;
  factory Definition(String filename) {
    var definition = definitions[filename];
    if (definition != null) {
      return definition;
    }

    var file = File(defsPath + filename);
    var contents = file.readAsStringSync();
    Map<String, dynamic> definitionData;
    try {
      dynamic parsedJson = json.decode(contents);
      if (parsedJson is Map<String, dynamic>) {
        definitionData = parsedJson;
      }
    } on FormatException catch (error) {
      color('Invalid json data in $filename: $error', front: Styles.RED);
      return null;
    }
    definitions[filename] =
        definition = Definition.fromFilename(filename, definitionData);
    return definition;
  }
  Definition.fromFilename(this._filename, Map<String, dynamic> data) {
    dynamic extendsFilename = data['extends'];
    if (extendsFilename is String) {
      _extensionOf = Definition(extendsFilename);
    }
    dynamic nameValue = data['name'];
    if (nameValue is String) {
      _name = nameValue;
    }
    dynamic abstractValue = data['abstract'];
    if (abstractValue is bool) {
      _isAbstract = abstractValue;
    }
    dynamic editorOnlyValue = data['editorOnly'];
    if (editorOnlyValue is bool) {
      _editorOnly = editorOnlyValue;
    }
    _key = Key.fromJSON(data['key']) ?? Key.forDefinition(this);

    dynamic properties = data['properties'];
    if (properties is Map<String, dynamic>) {
      for (final MapEntry<String, dynamic> entry in properties.entries) {
        if (entry.value is Map<String, dynamic>) {
          var property =
              Property(this, entry.key, entry.value as Map<String, dynamic>);
          if (property == null) {
            continue;
          }
          _properties.add(property);
        }
      }
    }
  }
  String get localFilename => _filename.indexOf(defsPath) == 0
      ? _filename.substring(defsPath.length)
      : _filename;

  String get name => _name;

  String get localCodeFilename => '${stripExtension(_filename)}_base.hpp';
  String get concreteCodeFilename => '${stripExtension(_filename)}.hpp';
  String get codeFilename => 'lib/src/generated/$localCodeFilename';

  /// Generates cpp header code based on the Definition
  Future<void> generateCode() async {
    bool defineContextExtension = _extensionOf?._name == null;
    StringBuffer code = StringBuffer();

    var includes = <String>{
      defineContextExtension ? 'core.hpp' : _extensionOf.concreteCodeFilename
    };
    for (final property in properties) {
      if (property.type.include != null) {
        includes.add(property.type.include);
      }
      includes.add(
          'core/field_types/' + property.type.snakeRuntimeCoreName + '.hpp');
    }

    var sortedIncludes = includes.toList()..sort();
    for (final include in sortedIncludes) {
      code.write('#include ');
      if (include[0] == '<') {
        code.write(include);
      } else {
        code.write('\"$include\"');
      }
      code.write('\n');
    }

    code.writeln('namespace rive {');
    var superTypeName = defineContextExtension ? 'Core' : _extensionOf?._name;
    code.writeln('class ${_name}Base : public $superTypeName {');

    code.writeln('protected:');
    code.writeln('typedef $superTypeName Super;');
    code.writeln('public:');
    code.writeln('static const uint16_t typeKey = ${_key.intValue};\n');

    code.write(comment(
        'Helper to quickly determine if a core object extends another '
        'without RTTI at runtime.',
        indent: 1));
    code.writeln('bool isTypeOf(uint16_t typeKey) const override {');

    code.writeln('switch(typeKey) {');
    code.writeln('case ${_name}Base::typeKey:');
    for (var p = _extensionOf; p != null; p = p._extensionOf) {
      code.writeln('case ${p._name}Base::typeKey:');
    }
    code.writeln('return true;');
    code.writeln('default: return false;}');

    code.writeln('}\n');

    code.writeln('uint16_t coreType() const override { return typeKey; }\n');
    if (properties.isNotEmpty) {
      for (final property in properties) {
        code.writeln('static const uint16_t ${property.name}PropertyKey = '
            '${property.key.intValue};');
      }
      code.writeln('private:');

      // Write fields.
      for (final property in properties) {
        code.writeln('${property.type.cppName} m_${property.capitalizedName}');

        var initialize = property.initialValueRuntime ??
            property.initialValue ??
            property.type.defaultValue;
        if (initialize != null) {
          code.write(' = ${property.type.convertCpp(initialize)}');
        }
        code.write(';');
      }

      // Write getter/setters.
      code.writeln('public:');
      for (final property in properties) {
        code.writeln(
            'inline ${property.type.cppGetterName} ${property.name}() const ' +
                (property.isGetOverride ? 'override' : '') +
                '{ return m_${property.capitalizedName}; }');

        code.writeln('void ${property.name}(${property.type.cppName} value) ' +
            (property.isSetOverride ? 'override' : '') +
            '{'
                'if(m_${property.capitalizedName} == value)'
                '{return;}'
                'm_${property.capitalizedName} = value;'
                '${property.name}Changed();'
                '}');

        code.writeln();
      }
    }

    if (properties.isNotEmpty || _extensionOf == null) {
      code.writeln('bool deserialize(uint16_t propertyKey, '
          'BinaryReader& reader) override {');

      code.writeln('switch (propertyKey){');
      for (final property in properties) {
        code.writeln('case ${property.name}PropertyKey:');
        code.writeln('m_${property.capitalizedName} = '
            '${property.type.runtimeCoreType}::deserialize(reader);');
        code.writeln('return true;');
      }
      code.writeln('}');
      if (_extensionOf != null) {
        code.writeln('return ${_extensionOf.name}::'
            'deserialize(propertyKey, reader); }');
      } else {
        code.writeln('return false; }');
      }
    }

    code.writeln('protected:');
    if (properties.isNotEmpty) {
      for (final property in properties) {
        code.writeln('virtual void ${property.name}Changed() {}');
      }
    }
    code.writeln('};');
    code.writeln('}');

    var file = File('$generatedHppPath$localCodeFilename');
    file.createSync(recursive: true);

    var formattedCode =
        await _formatter.formatAndGuard('${_name}Base', code.toString());
    file.writeAsStringSync(formattedCode, flush: true);

    // See if we need to stub out the concrete version...
    var concreteFile = File('$concreteHppPath$concreteCodeFilename');
    if (!concreteFile.existsSync()) {
      StringBuffer concreteCode = StringBuffer();
      concreteFile.createSync(recursive: true);
      concreteCode.writeln('#include "generated/$localCodeFilename"');
      concreteCode.writeln('#include <stdio.h>');
      concreteCode.writeln('namespace rive {');
      concreteCode.writeln('''class $_name : public ${_name}Base {
        public:
      };''');
      concreteCode.writeln('}');

      var formattedCode =
          await _formatter.formatAndGuard(_name, concreteCode.toString());
      concreteFile.writeAsStringSync(formattedCode, flush: true);
    }
  }

  @override
  String toString() {
    return '$_name[${_key?.intValue ?? '-'}]';
  }

  static const int minPropertyId = 3;
  static Future<bool> generate() async {
    // Check dupe ids.
    bool runGenerator = true;
    Map<int, Definition> ids = {};
    Map<int, Property> properties = {};
    for (final definition in definitions.values) {
      if (definition._key?.intValue != null) {
        var other = ids[definition._key.intValue];
        if (other != null) {
          color('Duplicate type ids for $definition and $other.',
              front: Styles.RED);
          runGenerator = false;
        } else {
          ids[definition._key.intValue] = definition;
        }
      }
      for (final property in definition._properties) {
        if (property.key.isMissing) {
          continue;
        }
        var other = properties[property.key.intValue];
        if (other != null) {
          color(
              '''Duplicate field ids for ${property.definition}.$property '''
              '''and ${other.definition}.$other.''',
              front: Styles.RED);
          runGenerator = false;
        } else if (property.key.intValue < minPropertyId) {
          color(
              '${property.definition}.$property: ids less than '
              '$minPropertyId are reserved.',
              front: Styles.RED);
          runGenerator = false;
        } else {
          properties[property.key.intValue] = property;
        }
      }
    }

    // Find max id, we use this to assign to types that don't have ids yet.
    int nextFieldId = minPropertyId - 1;
    int nextId = 0;
    for (final definition in definitions.values) {
      if (definition._key != null &&
          definition._key.intValue != null &&
          definition._key.intValue > nextId) {
        nextId = definition._key.intValue;
      }
      for (final field in definition._properties) {
        if (field != null &&
            field.key.intValue != null &&
            field.key.intValue > nextFieldId) {
          nextFieldId = field.key.intValue;
        }
      }
    }

    if (!runGenerator) {
      color('Not running generator due to previous errors.',
          front: Styles.YELLOW);
      return false;
    }

    definitions.removeWhere((key, definition) => definition._editorOnly);

    // Clear out previous generated code.
    var dir = Directory(generatedHppPath);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    dir.createSync(recursive: true);
    // Generate core context.

    for (final definition in definitions.values) {
      await definition.generateCode();
    }

    StringBuffer ctxCode = StringBuffer('');
    var includes = <String>{};
    for (final definition in definitions.values) {
      includes.add(definition.concreteCodeFilename);
    }
    var includeList = includes.toList()..sort();
    for (final include in includeList) {
      ctxCode.writeln('#include "$include"');
    }
    ctxCode.writeln('namespace rive {class CoreRegistry {'
        'public:');
    ctxCode.writeln('static Core* makeCoreInstance(int typeKey) {'
        'switch(typeKey) {');
    for (final definition in definitions.values) {
      if (definition._isAbstract) {
        continue;
      }
      ctxCode.writeln('case ${definition.name}Base::typeKey:');
      ctxCode.writeln('return new ${definition.name}();');
    }
    ctxCode.writeln('} return nullptr; }');

    var usedFieldTypes = <FieldType, List<Property>>{};
    for (final definition in definitions.values) {
      for (final property in definition.properties) {
        usedFieldTypes[property.type] ??= [];
        usedFieldTypes[property.type].add(property);
      }
    }
    for (final fieldType in usedFieldTypes.keys) {
      ctxCode
          .writeln('static void set${fieldType.capitalizedName}(Core* object, '
              'int propertyKey, ${fieldType.cppName} value){');
      ctxCode.writeln('switch (propertyKey) {');
      var properties = usedFieldTypes[fieldType];
      for (final property in properties) {
        ctxCode.writeln('case ${property.definition.name}Base'
            '::${property.name}PropertyKey:');
        ctxCode.writeln('object->as<${property.definition.name}Base>()->'
            '${property.name}(value);');
        ctxCode.writeln('break;');
      }
      ctxCode.writeln('}}');
    }
    for (final fieldType in usedFieldTypes.keys) {
      ctxCode.writeln(
          'static ${fieldType.cppName} get${fieldType.capitalizedName}('
          'Core* object, int propertyKey){');
      ctxCode.writeln('switch (propertyKey) {');
      var properties = usedFieldTypes[fieldType];
      for (final property in properties) {
        ctxCode.writeln('case ${property.definition.name}Base'
            '::${property.name}PropertyKey:');
        ctxCode.writeln('return object->as<${property.definition.name}Base>()->'
            '${property.name}();');
      }
      ctxCode.writeln('}');
      ctxCode.writeln('return ${fieldType.defaultValue ?? 'nullptr'};');
      ctxCode.writeln('}');
    }

    ctxCode.writeln('static int propertyFieldId(int propertyKey) {');
    ctxCode.writeln('switch(propertyKey) {');

    for (final fieldType in usedFieldTypes.keys) {
      var properties = usedFieldTypes[fieldType];
      for (final property in properties) {
        ctxCode.writeln('case ${property.definition.name}Base'
            '::${property.name}PropertyKey:');
      }
      ctxCode.writeln('return Core${fieldType.capitalizedName}Type::id;');
    }

    ctxCode.writeln('default: return -1;}}');
    /*Core makeCoreInstance(int typeKey) {
    switch (typeKey) {
      case KeyedObjectBase.typeKey:
        return KeyedObject();
      case KeyedPropertyBase.typeKey:
        return KeyedProperty();*/
    // Put our fields in.
    // var usedFieldTypes = <FieldType>{};
    // for (final definition in definitions.values) {
    //   for (final property in definition.properties) {
    //     usedFieldTypes.add(property.type);
    //   }
    // }
    // // Find fields we use.

    // for (final fieldType in usedFieldTypes) {
    //   ctxCode.writeln('static ${fieldType.runtimeCoreType} '
    //       '${fieldType.uncapitalizedName}Type;');
    // }
    ctxCode.writeln('};}');

    var output = generatedHppPath;
    var folder =
        output != null && output.isNotEmpty && output[output.length - 1] == '/'
            ? output.substring(0, output.length - 1)
            : output;

    var file = File('$folder/core_registry.hpp');
    file.createSync(recursive: true);

    var formattedCode =
        await _formatter.formatAndGuard('CoreRegistry', ctxCode.toString());
    file.writeAsStringSync(formattedCode, flush: true);

    return true;
  }
}
