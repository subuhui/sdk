// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This file contains logic which is shared between the ffi_definition and
// ffi_use_site transformers.

library vm.transformations.ffi;

import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart' show ClassHierarchy;
import 'package:kernel/core_types.dart';
import 'package:kernel/library_index.dart' show LibraryIndex;
import 'package:kernel/reference_from_index.dart';
import 'package:kernel/target/targets.dart' show DiagnosticReporter;
import 'package:kernel/type_algebra.dart' show Substitution;
import 'package:kernel/type_environment.dart'
    show TypeEnvironment, SubtypeCheckMode;

import 'abi.dart';

/// Represents the (instantiated) ffi.NativeType.
enum NativeType {
  kNativeType,
  kNativeInteger,
  kNativeDouble,
  kPointer,
  kNativeFunction,
  kInt8,
  kInt16,
  kInt32,
  kInt64,
  kUint8,
  kUint16,
  kUint32,
  kUint64,
  kIntptr,
  kFloat,
  kDouble,
  kVoid,
  kOpaque,
  kStruct,
  kHandle,
  kBool,
}

const Set<NativeType> nativeIntTypes = <NativeType>{
  NativeType.kInt8,
  NativeType.kInt16,
  NativeType.kInt32,
  NativeType.kInt64,
  NativeType.kUint8,
  NativeType.kUint16,
  NativeType.kUint32,
  NativeType.kUint64,
  NativeType.kIntptr,
};

/// The [NativeType] class names.
const Map<NativeType, String> nativeTypeClassNames = <NativeType, String>{
  NativeType.kNativeType: 'NativeType',
  NativeType.kNativeInteger: '_NativeInteger',
  NativeType.kNativeDouble: '_NativeDouble',
  NativeType.kPointer: 'Pointer',
  NativeType.kNativeFunction: 'NativeFunction',
  NativeType.kInt8: 'Int8',
  NativeType.kInt16: 'Int16',
  NativeType.kInt32: 'Int32',
  NativeType.kInt64: 'Int64',
  NativeType.kUint8: 'Uint8',
  NativeType.kUint16: 'Uint16',
  NativeType.kUint32: 'Uint32',
  NativeType.kUint64: 'Uint64',
  NativeType.kIntptr: 'IntPtr',
  NativeType.kFloat: 'Float',
  NativeType.kDouble: 'Double',
  NativeType.kVoid: 'Void',
  NativeType.kOpaque: 'Opaque',
  NativeType.kStruct: 'Struct',
  NativeType.kHandle: 'Handle',
  NativeType.kBool: 'Bool',
};

const int UNKNOWN = 0;
const int WORD_SIZE = -1;

/// The [NativeType] sizes in bytes.
const Map<NativeType, int> nativeTypeSizes = <NativeType, int>{
  NativeType.kNativeType: UNKNOWN,
  NativeType.kNativeInteger: UNKNOWN,
  NativeType.kNativeDouble: UNKNOWN,
  NativeType.kPointer: WORD_SIZE,
  NativeType.kNativeFunction: UNKNOWN,
  NativeType.kInt8: 1,
  NativeType.kInt16: 2,
  NativeType.kInt32: 4,
  NativeType.kInt64: 8,
  NativeType.kUint8: 1,
  NativeType.kUint16: 2,
  NativeType.kUint32: 4,
  NativeType.kUint64: 8,
  NativeType.kIntptr: WORD_SIZE,
  NativeType.kFloat: 4,
  NativeType.kDouble: 8,
  NativeType.kVoid: UNKNOWN,
  NativeType.kOpaque: UNKNOWN,
  NativeType.kStruct: UNKNOWN,
  NativeType.kHandle: WORD_SIZE,
  NativeType.kBool: 1,
};

/// Load, store, and elementAt are rewired to their static type for these types.
const List<NativeType> optimizedTypes = [
  NativeType.kBool,
  NativeType.kInt8,
  NativeType.kInt16,
  NativeType.kInt32,
  NativeType.kInt64,
  NativeType.kUint8,
  NativeType.kUint16,
  NativeType.kUint32,
  NativeType.kUint64,
  NativeType.kIntptr,
  NativeType.kFloat,
  NativeType.kDouble,
  NativeType.kPointer,
];

const List<NativeType> unalignedLoadsStores = [
  NativeType.kFloat,
  NativeType.kDouble,
];

/// [FfiTransformer] contains logic which is shared between
/// _FfiUseSiteTransformer and _FfiDefinitionTransformer.
class FfiTransformer extends Transformer {
  final TypeEnvironment env;
  final CoreTypes coreTypes;
  final LibraryIndex index;
  final ClassHierarchy hierarchy;
  final DiagnosticReporter diagnosticReporter;
  final ReferenceFromIndex? referenceFromIndex;

  final Class objectClass;
  final Class intClass;
  final Class doubleClass;
  final Class boolClass;
  final Class listClass;
  final Class typeClass;
  final Procedure unsafeCastMethod;
  final Procedure nativeEffectMethod;
  final Class typedDataClass;
  final Procedure typedDataBufferGetter;
  final Procedure typedDataOffsetInBytesGetter;
  final Procedure byteBufferAsUint8List;
  final Procedure uint8ListFactory;
  final Class pragmaClass;
  final Field pragmaName;
  final Field pragmaOptions;
  final Procedure listElementAt;
  final Procedure numAddition;
  final Procedure numMultiplication;

  final Library ffiLibrary;
  final Class allocatorClass;
  final Class nativeFunctionClass;
  final Class handleClass;
  final Class opaqueClass;
  final Class arrayClass;
  final Class arraySizeClass;
  final Field arraySizeDimension1Field;
  final Field arraySizeDimension2Field;
  final Field arraySizeDimension3Field;
  final Field arraySizeDimension4Field;
  final Field arraySizeDimension5Field;
  final Field arraySizeDimensionsField;
  final Class pointerClass;
  final Class compoundClass;
  final Class structClass;
  final Class unionClass;
  final Class ffiNativeClass;
  final Class nativeFieldWrapperClass1Class;
  final Class ffiStructLayoutClass;
  final Field ffiStructLayoutTypesField;
  final Field ffiStructLayoutPackingField;
  final Class ffiInlineArrayClass;
  final Field ffiInlineArrayElementTypeField;
  final Field ffiInlineArrayLengthField;
  final Class packedClass;
  final Field packedMemberAlignmentField;
  final Procedure allocateMethod;
  final Procedure allocatorAllocateMethod;
  final Procedure castMethod;
  final Procedure offsetByMethod;
  final Procedure elementAtMethod;
  final Procedure addressGetter;
  final Procedure structPointerRef;
  final Procedure structPointerElemAt;
  final Procedure unionPointerRef;
  final Procedure unionPointerElemAt;
  final Procedure structArrayElemAt;
  final Procedure unionArrayElemAt;
  final Procedure arrayArrayElemAt;
  final Procedure arrayArrayAssignAt;
  final Procedure asFunctionMethod;
  final Procedure asFunctionInternal;
  final Procedure sizeOfMethod;
  final Procedure lookupFunctionMethod;
  final Procedure fromFunctionMethod;
  final Field compoundTypedDataBaseField;
  final Field arrayTypedDataBaseField;
  final Field arraySizeField;
  final Field arrayNestedDimensionsField;
  final Procedure arrayCheckIndex;
  final Field arrayNestedDimensionsFlattened;
  final Field arrayNestedDimensionsFirst;
  final Field arrayNestedDimensionsRest;
  final Constructor structFromTypedDataBase;
  final Constructor unionFromTypedDataBase;
  final Constructor arrayConstructor;
  final Procedure fromAddressInternal;
  final Procedure libraryLookupMethod;
  final Procedure abiMethod;
  final Procedure pointerFromFunctionProcedure;
  final Procedure nativeCallbackFunctionProcedure;
  final Map<NativeType, Procedure> loadMethods;
  final Map<NativeType, Procedure> loadUnalignedMethods;
  final Map<NativeType, Procedure> storeMethods;
  final Map<NativeType, Procedure> storeUnalignedMethods;
  final Map<NativeType, Procedure> elementAtMethods;
  final Procedure memCopy;
  final Procedure allocationTearoff;
  final Procedure asFunctionTearoff;
  final Procedure lookupFunctionTearoff;
  final Procedure getNativeFieldFunction;
  final Procedure reachabilityFenceFunction;
  final Procedure checkAbiSpecificIntegerMappingFunction;

  late final InterfaceType nativeFieldWrapperClass1Type;
  late final InterfaceType voidType;
  late final InterfaceType pointerVoidType;

  /// Classes corresponding to [NativeType], indexed by [NativeType].
  final Map<NativeType, Class> nativeTypesClasses;
  final Map<Class, NativeType> classNativeTypes;

  Library? _currentLibrary;
  Library get currentLibrary => _currentLibrary!;

  IndexedLibrary? currentLibraryIndex;

  FfiTransformer(this.index, this.coreTypes, this.hierarchy,
      this.diagnosticReporter, this.referenceFromIndex)
      : env = TypeEnvironment(coreTypes, hierarchy),
        objectClass = coreTypes.objectClass,
        intClass = coreTypes.intClass,
        doubleClass = coreTypes.doubleClass,
        boolClass = coreTypes.boolClass,
        listClass = coreTypes.listClass,
        typeClass = coreTypes.typeClass,
        unsafeCastMethod =
            index.getTopLevelProcedure('dart:_internal', 'unsafeCast'),
        nativeEffectMethod =
            index.getTopLevelProcedure('dart:_internal', '_nativeEffect'),
        typedDataClass = index.getClass('dart:typed_data', 'TypedData'),
        typedDataBufferGetter =
            index.getProcedure('dart:typed_data', 'TypedData', 'get:buffer'),
        typedDataOffsetInBytesGetter = index.getProcedure(
            'dart:typed_data', 'TypedData', 'get:offsetInBytes'),
        byteBufferAsUint8List =
            index.getProcedure('dart:typed_data', 'ByteBuffer', 'asUint8List'),
        uint8ListFactory =
            index.getProcedure('dart:typed_data', 'Uint8List', ''),
        pragmaClass = coreTypes.pragmaClass,
        pragmaName = coreTypes.pragmaName,
        pragmaOptions = coreTypes.pragmaOptions,
        listElementAt = coreTypes.index.getProcedure('dart:core', 'List', '[]'),
        numAddition = coreTypes.index.getProcedure('dart:core', 'num', '+'),
        numMultiplication =
            coreTypes.index.getProcedure('dart:core', 'num', '*'),
        ffiLibrary = index.getLibrary('dart:ffi'),
        allocatorClass = index.getClass('dart:ffi', 'Allocator'),
        nativeFunctionClass = index.getClass('dart:ffi', 'NativeFunction'),
        handleClass = index.getClass('dart:ffi', 'Handle'),
        opaqueClass = index.getClass('dart:ffi', 'Opaque'),
        arrayClass = index.getClass('dart:ffi', 'Array'),
        arraySizeClass = index.getClass('dart:ffi', '_ArraySize'),
        arraySizeDimension1Field =
            index.getField('dart:ffi', '_ArraySize', 'dimension1'),
        arraySizeDimension2Field =
            index.getField('dart:ffi', '_ArraySize', 'dimension2'),
        arraySizeDimension3Field =
            index.getField('dart:ffi', '_ArraySize', 'dimension3'),
        arraySizeDimension4Field =
            index.getField('dart:ffi', '_ArraySize', 'dimension4'),
        arraySizeDimension5Field =
            index.getField('dart:ffi', '_ArraySize', 'dimension5'),
        arraySizeDimensionsField =
            index.getField('dart:ffi', '_ArraySize', 'dimensions'),
        pointerClass = index.getClass('dart:ffi', 'Pointer'),
        compoundClass = index.getClass('dart:ffi', '_Compound'),
        structClass = index.getClass('dart:ffi', 'Struct'),
        unionClass = index.getClass('dart:ffi', 'Union'),
        ffiNativeClass = index.getClass('dart:ffi', 'FfiNative'),
        nativeFieldWrapperClass1Class =
            index.getClass('dart:nativewrappers', 'NativeFieldWrapperClass1'),
        ffiStructLayoutClass = index.getClass('dart:ffi', '_FfiStructLayout'),
        ffiStructLayoutTypesField =
            index.getField('dart:ffi', '_FfiStructLayout', 'fieldTypes'),
        ffiStructLayoutPackingField =
            index.getField('dart:ffi', '_FfiStructLayout', 'packing'),
        ffiInlineArrayClass = index.getClass('dart:ffi', '_FfiInlineArray'),
        ffiInlineArrayElementTypeField =
            index.getField('dart:ffi', '_FfiInlineArray', 'elementType'),
        ffiInlineArrayLengthField =
            index.getField('dart:ffi', '_FfiInlineArray', 'length'),
        packedClass = index.getClass('dart:ffi', 'Packed'),
        packedMemberAlignmentField =
            index.getField('dart:ffi', 'Packed', 'memberAlignment'),
        allocateMethod =
            index.getProcedure('dart:ffi', 'AllocatorAlloc', 'call'),
        allocatorAllocateMethod =
            index.getProcedure('dart:ffi', 'Allocator', 'allocate'),
        castMethod = index.getProcedure('dart:ffi', 'Pointer', 'cast'),
        offsetByMethod = index.getProcedure('dart:ffi', 'Pointer', '_offsetBy'),
        elementAtMethod =
            index.getProcedure('dart:ffi', 'Pointer', 'elementAt'),
        addressGetter =
            index.getProcedure('dart:ffi', 'Pointer', 'get:address'),
        compoundTypedDataBaseField =
            index.getField('dart:ffi', '_Compound', '_typedDataBase'),
        arrayTypedDataBaseField =
            index.getField('dart:ffi', 'Array', '_typedDataBase'),
        arraySizeField = index.getField('dart:ffi', 'Array', '_size'),
        arrayNestedDimensionsField =
            index.getField('dart:ffi', 'Array', '_nestedDimensions'),
        arrayCheckIndex =
            index.getProcedure('dart:ffi', 'Array', '_checkIndex'),
        arrayNestedDimensionsFlattened =
            index.getField('dart:ffi', 'Array', '_nestedDimensionsFlattened'),
        arrayNestedDimensionsFirst =
            index.getField('dart:ffi', 'Array', '_nestedDimensionsFirst'),
        arrayNestedDimensionsRest =
            index.getField('dart:ffi', 'Array', '_nestedDimensionsRest'),
        structFromTypedDataBase =
            index.getConstructor('dart:ffi', 'Struct', '_fromTypedDataBase'),
        unionFromTypedDataBase =
            index.getConstructor('dart:ffi', 'Union', '_fromTypedDataBase'),
        arrayConstructor = index.getConstructor('dart:ffi', 'Array', '_'),
        fromAddressInternal =
            index.getTopLevelProcedure('dart:ffi', '_fromAddress'),
        structPointerRef =
            index.getProcedure('dart:ffi', 'StructPointer', 'get:ref'),
        structPointerElemAt =
            index.getProcedure('dart:ffi', 'StructPointer', '[]'),
        unionPointerRef =
            index.getProcedure('dart:ffi', 'UnionPointer', 'get:ref'),
        unionPointerElemAt =
            index.getProcedure('dart:ffi', 'UnionPointer', '[]'),
        structArrayElemAt = index.getProcedure('dart:ffi', 'StructArray', '[]'),
        unionArrayElemAt = index.getProcedure('dart:ffi', 'UnionArray', '[]'),
        arrayArrayElemAt = index.getProcedure('dart:ffi', 'ArrayArray', '[]'),
        arrayArrayAssignAt =
            index.getProcedure('dart:ffi', 'ArrayArray', '[]='),
        asFunctionMethod = index.getProcedure(
            'dart:ffi', 'NativeFunctionPointer', 'asFunction'),
        asFunctionInternal =
            index.getTopLevelProcedure('dart:ffi', '_asFunctionInternal'),
        sizeOfMethod = index.getTopLevelProcedure('dart:ffi', 'sizeOf'),
        lookupFunctionMethod = index.getProcedure(
            'dart:ffi', 'DynamicLibraryExtension', 'lookupFunction'),
        fromFunctionMethod =
            index.getProcedure('dart:ffi', 'Pointer', 'fromFunction'),
        libraryLookupMethod =
            index.getProcedure('dart:ffi', 'DynamicLibrary', 'lookup'),
        abiMethod = index.getTopLevelProcedure('dart:ffi', '_abi'),
        pointerFromFunctionProcedure =
            index.getTopLevelProcedure('dart:ffi', '_pointerFromFunction'),
        nativeCallbackFunctionProcedure =
            index.getTopLevelProcedure('dart:ffi', '_nativeCallbackFunction'),
        nativeTypesClasses = nativeTypeClassNames.map((nativeType, name) =>
            MapEntry(nativeType, index.getClass('dart:ffi', name))),
        classNativeTypes = nativeTypeClassNames.map((nativeType, name) =>
            MapEntry(index.getClass('dart:ffi', name), nativeType)),
        loadMethods = Map.fromIterable(optimizedTypes, value: (t) {
          final name = nativeTypeClassNames[t];
          return index.getTopLevelProcedure('dart:ffi', "_load$name");
        }),
        loadUnalignedMethods =
            Map.fromIterable(unalignedLoadsStores, value: (t) {
          final name = nativeTypeClassNames[t];
          return index.getTopLevelProcedure(
              'dart:ffi', "_load${name}Unaligned");
        }),
        storeMethods = Map.fromIterable(optimizedTypes, value: (t) {
          final name = nativeTypeClassNames[t];
          return index.getTopLevelProcedure('dart:ffi', "_store$name");
        }),
        storeUnalignedMethods =
            Map.fromIterable(unalignedLoadsStores, value: (t) {
          final name = nativeTypeClassNames[t];
          return index.getTopLevelProcedure(
              'dart:ffi', "_store${name}Unaligned");
        }),
        elementAtMethods = Map.fromIterable(optimizedTypes, value: (t) {
          final name = nativeTypeClassNames[t];
          return index.getTopLevelProcedure('dart:ffi', "_elementAt$name");
        }),
        memCopy = index.getTopLevelProcedure('dart:ffi', '_memCopy'),
        allocationTearoff = index.getProcedure(
            'dart:ffi', 'AllocatorAlloc', LibraryIndex.tearoffPrefix + 'call'),
        asFunctionTearoff = index.getProcedure('dart:ffi',
            'NativeFunctionPointer', LibraryIndex.tearoffPrefix + 'asFunction'),
        lookupFunctionTearoff = index.getProcedure(
            'dart:ffi',
            'DynamicLibraryExtension',
            LibraryIndex.tearoffPrefix + 'lookupFunction'),
        getNativeFieldFunction = index.getTopLevelProcedure(
            'dart:nativewrappers', '_getNativeField'),
        reachabilityFenceFunction =
            index.getTopLevelProcedure('dart:_internal', 'reachabilityFence'),
        checkAbiSpecificIntegerMappingFunction = index.getTopLevelProcedure(
            'dart:ffi', "_checkAbiSpecificIntegerMapping") {
    nativeFieldWrapperClass1Type = nativeFieldWrapperClass1Class.getThisType(
        coreTypes, Nullability.nonNullable);
    voidType = nativeTypesClasses[NativeType.kVoid]!
        .getThisType(coreTypes, Nullability.nonNullable);
    pointerVoidType =
        InterfaceType(pointerClass, Nullability.nonNullable, [voidType]);
  }

  @override
  TreeNode visitLibrary(Library node) {
    assert(_currentLibrary == null);
    _currentLibrary = node;
    currentLibraryIndex = referenceFromIndex?.lookupLibrary(node);
    final result = super.visitLibrary(node);
    _currentLibrary = null;
    return result;
  }

  /// Computes the Dart type corresponding to a ffi.[NativeType], returns null
  /// if it is not a valid NativeType.
  ///
  /// [Int8]                               -> [int]
  /// [Int16]                              -> [int]
  /// [Int32]                              -> [int]
  /// [Int64]                              -> [int]
  /// [Uint8]                              -> [int]
  /// [Uint16]                             -> [int]
  /// [Uint32]                             -> [int]
  /// [Uint64]                             -> [int]
  /// [IntPtr]                             -> [int]
  /// [Double]                             -> [double]
  /// [Float]                              -> [double]
  /// [Bool]                               -> [bool]
  /// [Void]                               -> [void]
  /// [Pointer]<T>                         -> [Pointer]<T>
  /// T extends [Compound]                 -> T
  /// [Handle]                             -> [Object]
  /// [NativeFunction]<T1 Function(T2, T3) -> S1 Function(S2, S3)
  ///    where DartRepresentationOf(Tn) -> Sn
  DartType? convertNativeTypeToDartType(DartType nativeType,
      {bool allowCompounds = false,
      bool allowHandle = false,
      bool allowInlineArray = false}) {
    if (nativeType is! InterfaceType) {
      return null;
    }
    final InterfaceType native = nativeType;
    final Class nativeClass = native.classNode;
    final NativeType? nativeType_ = getType(nativeClass);

    if (nativeClass == arrayClass) {
      if (!allowInlineArray) {
        return null;
      }
      return nativeType;
    }
    if (hierarchy.isSubclassOf(nativeClass, compoundClass)) {
      if (nativeClass == structClass || nativeClass == unionClass) {
        return null;
      }
      return allowCompounds ? nativeType : null;
    }
    if (nativeType_ == null) {
      return null;
    }
    if (nativeType_ == NativeType.kPointer) {
      return nativeType;
    }
    if (nativeIntTypes.contains(nativeType_)) {
      return InterfaceType(intClass, Nullability.legacy);
    }
    if (nativeType_ == NativeType.kFloat || nativeType_ == NativeType.kDouble) {
      return InterfaceType(doubleClass, Nullability.legacy);
    }
    if (nativeType_ == NativeType.kBool) {
      return InterfaceType(boolClass, Nullability.legacy);
    }
    if (nativeType_ == NativeType.kVoid) {
      return VoidType();
    }
    if (nativeType_ == NativeType.kHandle && allowHandle) {
      return InterfaceType(objectClass, Nullability.legacy);
    }
    if (nativeType_ != NativeType.kNativeFunction ||
        native.typeArguments[0] is! FunctionType) {
      return null;
    }

    final FunctionType fun = native.typeArguments[0] as FunctionType;
    if (fun.namedParameters.isNotEmpty) return null;
    if (fun.positionalParameters.length != fun.requiredParameterCount) {
      return null;
    }
    if (fun.typeParameters.length != 0) return null;

    final DartType? returnType = convertNativeTypeToDartType(fun.returnType,
        allowCompounds: true, allowHandle: true);
    if (returnType == null) return null;
    final List<DartType> argumentTypes = fun.positionalParameters
        .map((t) =>
            convertNativeTypeToDartType(t,
                allowCompounds: true, allowHandle: true) ??
            dummyDartType)
        .toList();
    if (argumentTypes.contains(dummyDartType)) return null;
    return FunctionType(argumentTypes, returnType, Nullability.legacy);
  }

  /// The [NativeType] corresponding to [c]. Returns `null` for user-defined
  /// structs.
  NativeType? getType(Class c) {
    return classNativeTypes[c];
  }

  InterfaceType _listOfIntType() => InterfaceType(
      listClass, Nullability.legacy, [coreTypes.intLegacyRawType]);

  ConstantExpression intListConstantExpression(List<int?> values) =>
      ConstantExpression(
          ListConstant(coreTypes.intLegacyRawType, [
            for (var v in values)
              if (v != null) IntConstant(v) else NullConstant()
          ]),
          _listOfIntType());

  /// Expression that queries VM internals at runtime to figure out on which ABI
  /// we are.
  Expression runtimeBranchOnLayout(Map<Abi, int?> values) {
    final result = InstanceInvocation(
        InstanceAccessKind.Instance,
        intListConstantExpression([
          for (final abi in Abi.values) values[abi],
        ]),
        listElementAt.name,
        Arguments([StaticInvocation(abiMethod, Arguments([]))]),
        interfaceTarget: listElementAt,
        functionType: Substitution.fromInterfaceType(_listOfIntType())
            .substituteType(listElementAt.getterType) as FunctionType);
    if (values.isPartial) {
      return checkAbiSpecificIntegerMapping(result);
    }
    return result;
  }

  Expression checkAbiSpecificIntegerMapping(Expression nullableExpression) =>
      StaticInvocation(
        checkAbiSpecificIntegerMappingFunction,
        Arguments(
          [nullableExpression],
          types: [InterfaceType(intClass, Nullability.nonNullable)],
        ),
      );

  /// Generates an expression that returns a new `Pointer<dartType>` offset
  /// by [offset] from [pointer].
  ///
  /// Sample output:
  ///
  /// ```
  /// _fromAddress<dartType>(pointer.address + #offset)
  /// ```
  Expression _pointerOffset(Expression pointer, Expression offset,
          DartType dartType, int fileOffset) =>
      StaticInvocation(
          fromAddressInternal,
          Arguments([
            add(
                InstanceGet(
                    InstanceAccessKind.Instance, pointer, addressGetter.name,
                    interfaceTarget: addressGetter,
                    resultType: addressGetter.getterType)
                  ..fileOffset = fileOffset,
                offset)
          ], types: [
            dartType
          ]))
        ..fileOffset = fileOffset;

  /// Generates an expression that returns a new `TypedData` offset
  /// by [offset] from [typedData].
  ///
  /// Sample output:
  ///
  /// ```
  /// TypedData #typedData = typedData;
  /// #typedData.buffer.asInt8List(#typedData.offsetInBytes + offset, length)
  /// ```
  Expression _typedDataOffset(Expression typedData, Expression offset,
      Expression length, int fileOffset) {
    final typedDataVar = VariableDeclaration("#typedData",
        initializer: typedData,
        type: InterfaceType(typedDataClass, Nullability.nonNullable))
      ..fileOffset = fileOffset;
    return Let(
        typedDataVar,
        InstanceInvocation(
            InstanceAccessKind.Instance,
            InstanceGet(InstanceAccessKind.Instance, VariableGet(typedDataVar),
                typedDataBufferGetter.name,
                interfaceTarget: typedDataBufferGetter,
                resultType: typedDataBufferGetter.getterType)
              ..fileOffset = fileOffset,
            byteBufferAsUint8List.name,
            Arguments([
              add(
                  InstanceGet(
                      InstanceAccessKind.Instance,
                      VariableGet(typedDataVar),
                      typedDataOffsetInBytesGetter.name,
                      interfaceTarget: typedDataOffsetInBytesGetter,
                      resultType: typedDataOffsetInBytesGetter.getterType)
                    ..fileOffset = fileOffset,
                  offset),
              length
            ]),
            interfaceTarget: byteBufferAsUint8List,
            functionType: byteBufferAsUint8List.getterType as FunctionType));
  }

  /// Generates an expression that returns a new `TypedDataBase` offset
  /// by [offset] from [typedDataBase].
  ///
  /// If [typedDataBase] is a `Pointer`, returns a `Pointer<dartType>`.
  /// If [typedDataBase] is a `TypedData` returns a `TypedData`.
  ///
  /// Sample output:
  ///
  /// ```
  /// Object #typedDataBase = typedDataBase;
  /// int #offset = offset;
  /// #typedDataBase is Pointer ?
  ///   _pointerOffset<dartType>(#typedDataBase, #offset) :
  ///   _typedDataOffset((#typedDataBase as TypedData), #offset, length)
  /// ```
  Expression typedDataBaseOffset(Expression typedDataBase, Expression offset,
      Expression length, DartType dartType, int fileOffset) {
    final typedDataBaseVar = VariableDeclaration("#typedDataBase",
        initializer: typedDataBase, type: coreTypes.objectNonNullableRawType)
      ..fileOffset = fileOffset;
    final offsetVar = VariableDeclaration("#offset",
        initializer: offset, type: coreTypes.intNonNullableRawType)
      ..fileOffset = fileOffset;
    return BlockExpression(
        Block([typedDataBaseVar, offsetVar]),
        ConditionalExpression(
            IsExpression(VariableGet(typedDataBaseVar),
                InterfaceType(pointerClass, Nullability.nonNullable)),
            _pointerOffset(VariableGet(typedDataBaseVar),
                VariableGet(offsetVar), dartType, fileOffset),
            _typedDataOffset(
                StaticInvocation(
                    unsafeCastMethod,
                    Arguments([
                      VariableGet(typedDataBaseVar)
                    ], types: [
                      InterfaceType(typedDataClass, Nullability.nonNullable)
                    ])),
                VariableGet(offsetVar),
                length,
                fileOffset),
            coreTypes.objectNonNullableRawType));
  }

  bool isPrimitiveType(DartType type) {
    if (type is InvalidType) {
      return false;
    }
    if (type is NullType) {
      return false;
    }
    if (!env.isSubtypeOf(
        type,
        InterfaceType(
            nativeTypesClasses[NativeType.kNativeType]!, Nullability.legacy),
        SubtypeCheckMode.ignoringNullabilities)) {
      return false;
    }
    if (isPointerType(type)) {
      return false;
    }
    if (type is InterfaceType) {
      final nativeType = getType(type.classNode);
      return nativeType != null;
    }
    return false;
  }

  bool isPointerType(DartType type) {
    if (type is InvalidType) {
      return false;
    }
    if (type is NullType) {
      return false;
    }
    return env.isSubtypeOf(
        type,
        InterfaceType(pointerClass, Nullability.legacy, [
          InterfaceType(
              nativeTypesClasses[NativeType.kNativeType]!, Nullability.legacy)
        ]),
        SubtypeCheckMode.ignoringNullabilities);
  }

  bool isArrayType(DartType type) {
    if (type is InvalidType) {
      return false;
    }
    if (type is NullType) {
      return false;
    }
    return env.isSubtypeOf(
        type,
        InterfaceType(arrayClass, Nullability.legacy, [
          InterfaceType(
              nativeTypesClasses[NativeType.kNativeType]!, Nullability.legacy)
        ]),
        SubtypeCheckMode.ignoringNullabilities);
  }

  /// Returns the single element type nested type argument of `Array`.
  ///
  /// `Array<Array<Array<Int8>>>` -> `Int8`.
  ///
  /// `Array<Array<Array<Unknown>>>` -> [InvalidType].
  DartType arraySingleElementType(DartType dartType) {
    InterfaceType elementType = dartType as InterfaceType;
    while (elementType.classNode == arrayClass) {
      final elementTypeAny = elementType.typeArguments[0];
      if (elementTypeAny is InvalidType) {
        return elementTypeAny;
      }
      elementType = elementTypeAny as InterfaceType;
    }
    return elementType;
  }

  /// Returns the number of dimensions of `Array`.
  ///
  /// `Array<Array<Array<Int8>>>` -> 3.
  ///
  /// `Array<Array<Array<Unknown>>>` -> 3.
  int arrayDimensions(DartType dartType) {
    DartType elementType = dartType;
    int dimensions = 0;
    while (
        elementType is InterfaceType && elementType.classNode == arrayClass) {
      elementType = elementType.typeArguments[0];
      dimensions++;
    }
    return dimensions;
  }

  bool isCompoundSubtype(DartType type) {
    if (type is InvalidType) {
      return false;
    }
    if (type is NullType) {
      return false;
    }
    if (type is InterfaceType) {
      if (type.classNode == structClass || type.classNode == unionClass) {
        return false;
      }
    }
    return env.isSubtypeOf(
        type,
        InterfaceType(compoundClass, Nullability.legacy),
        SubtypeCheckMode.ignoringNullabilities);
  }

  Expression getCompoundTypedDataBaseField(
      Expression receiver, int fileOffset) {
    return InstanceGet(
        InstanceAccessKind.Instance, receiver, compoundTypedDataBaseField.name,
        interfaceTarget: compoundTypedDataBaseField,
        resultType: compoundTypedDataBaseField.type)
      ..fileOffset = fileOffset;
  }

  Expression getArrayTypedDataBaseField(Expression receiver,
      [int fileOffset = TreeNode.noOffset]) {
    return InstanceGet(
        InstanceAccessKind.Instance, receiver, arrayTypedDataBaseField.name,
        interfaceTarget: arrayTypedDataBaseField,
        resultType: arrayTypedDataBaseField.type)
      ..fileOffset = fileOffset;
  }

  Expression add(Expression a, Expression b) {
    return InstanceInvocation(
        InstanceAccessKind.Instance, a, numAddition.name, Arguments([b]),
        interfaceTarget: numAddition,
        functionType: numAddition.getterType as FunctionType);
  }

  Expression multiply(Expression a, Expression b) {
    return InstanceInvocation(
        InstanceAccessKind.Instance, a, numMultiplication.name, Arguments([b]),
        interfaceTarget: numMultiplication,
        functionType: numMultiplication.getterType as FunctionType);
  }
}

/// Checks if any library depends on dart:ffi.
bool importsFfi(Component component, List<Library> libraries) {
  Set<Library> allLibs = {...component.libraries, ...libraries};
  final Uri dartFfiUri = Uri.parse("dart:ffi");
  for (Library lib in allLibs) {
    for (LibraryDependency dependency in lib.dependencies) {
      if (dependency.targetLibrary.importUri == dartFfiUri) {
        return true;
      }
    }
  }
  return false;
}

extension on Map<Abi, Object?> {
  bool get isPartial =>
      [for (final abi in Abi.values) this[abi]].contains(null);
}
