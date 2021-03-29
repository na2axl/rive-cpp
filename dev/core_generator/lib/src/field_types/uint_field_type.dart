import '../field_type.dart';

class UintFieldType extends FieldType {
  UintFieldType()
      : super(
          'uint',
          'CoreUintType',
          cppName: 'int',
        );

  @override
  String get defaultValue => '0';

  // We do this to fix up CoreContext.invalidProperyKey
  @override
  String convertCpp(String value) => value.replaceAll('CoreContext.', 'Core::');
}
