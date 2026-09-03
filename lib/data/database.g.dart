// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ContactsTable extends Contacts with TableInfo<$ContactsTable, Contact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _publicKeyHexMeta =
      const VerificationMeta('publicKeyHex');
  @override
  late final GeneratedColumn<String> publicKeyHex = GeneratedColumn<String>(
      'public_key_hex', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _nicknameMeta =
      const VerificationMeta('nickname');
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
      'nickname', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [id, publicKeyHex, nickname, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'contacts';
  @override
  VerificationContext validateIntegrity(Insertable<Contact> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('public_key_hex')) {
      context.handle(
          _publicKeyHexMeta,
          publicKeyHex.isAcceptableOrUnknown(
              data['public_key_hex']!, _publicKeyHexMeta));
    } else if (isInserting) {
      context.missing(_publicKeyHexMeta);
    }
    if (data.containsKey('nickname')) {
      context.handle(_nicknameMeta,
          nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta));
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Contact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Contact(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      publicKeyHex: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}public_key_hex'])!,
      nickname: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}nickname']),
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
    );
  }

  @override
  $ContactsTable createAlias(String alias) {
    return $ContactsTable(attachedDatabase, alias);
  }
}

class Contact extends DataClass implements Insertable<Contact> {
  final int id;
  final String publicKeyHex;
  final String? nickname;
  final DateTime addedAt;
  const Contact(
      {required this.id,
      required this.publicKeyHex,
      this.nickname,
      required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['public_key_hex'] = Variable<String>(publicKeyHex);
    if (!nullToAbsent || nickname != null) {
      map['nickname'] = Variable<String>(nickname);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  ContactsCompanion toCompanion(bool nullToAbsent) {
    return ContactsCompanion(
      id: Value(id),
      publicKeyHex: Value(publicKeyHex),
      nickname: nickname == null && nullToAbsent
          ? const Value.absent()
          : Value(nickname),
      addedAt: Value(addedAt),
    );
  }

  factory Contact.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Contact(
      id: serializer.fromJson<int>(json['id']),
      publicKeyHex: serializer.fromJson<String>(json['publicKeyHex']),
      nickname: serializer.fromJson<String?>(json['nickname']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'publicKeyHex': serializer.toJson<String>(publicKeyHex),
      'nickname': serializer.toJson<String?>(nickname),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  Contact copyWith(
          {int? id,
          String? publicKeyHex,
          Value<String?> nickname = const Value.absent(),
          DateTime? addedAt}) =>
      Contact(
        id: id ?? this.id,
        publicKeyHex: publicKeyHex ?? this.publicKeyHex,
        nickname: nickname.present ? nickname.value : this.nickname,
        addedAt: addedAt ?? this.addedAt,
      );
  Contact copyWithCompanion(ContactsCompanion data) {
    return Contact(
      id: data.id.present ? data.id.value : this.id,
      publicKeyHex: data.publicKeyHex.present
          ? data.publicKeyHex.value
          : this.publicKeyHex,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Contact(')
          ..write('id: $id, ')
          ..write('publicKeyHex: $publicKeyHex, ')
          ..write('nickname: $nickname, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, publicKeyHex, nickname, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Contact &&
          other.id == this.id &&
          other.publicKeyHex == this.publicKeyHex &&
          other.nickname == this.nickname &&
          other.addedAt == this.addedAt);
}

class ContactsCompanion extends UpdateCompanion<Contact> {
  final Value<int> id;
  final Value<String> publicKeyHex;
  final Value<String?> nickname;
  final Value<DateTime> addedAt;
  const ContactsCompanion({
    this.id = const Value.absent(),
    this.publicKeyHex = const Value.absent(),
    this.nickname = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  ContactsCompanion.insert({
    this.id = const Value.absent(),
    required String publicKeyHex,
    this.nickname = const Value.absent(),
    this.addedAt = const Value.absent(),
  }) : publicKeyHex = Value(publicKeyHex);
  static Insertable<Contact> custom({
    Expression<int>? id,
    Expression<String>? publicKeyHex,
    Expression<String>? nickname,
    Expression<DateTime>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (publicKeyHex != null) 'public_key_hex': publicKeyHex,
      if (nickname != null) 'nickname': nickname,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  ContactsCompanion copyWith(
      {Value<int>? id,
      Value<String>? publicKeyHex,
      Value<String?>? nickname,
      Value<DateTime>? addedAt}) {
    return ContactsCompanion(
      id: id ?? this.id,
      publicKeyHex: publicKeyHex ?? this.publicKeyHex,
      nickname: nickname ?? this.nickname,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (publicKeyHex.present) {
      map['public_key_hex'] = Variable<String>(publicKeyHex.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContactsCompanion(')
          ..write('id: $id, ')
          ..write('publicKeyHex: $publicKeyHex, ')
          ..write('nickname: $nickname, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _contactPublicKeyHexMeta =
      const VerificationMeta('contactPublicKeyHex');
  @override
  late final GeneratedColumn<String> contactPublicKeyHex =
      GeneratedColumn<String>('contact_public_key_hex', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _outgoingMeta =
      const VerificationMeta('outgoing');
  @override
  late final GeneratedColumn<bool> outgoing = GeneratedColumn<bool>(
      'outgoing', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("outgoing" IN (0, 1))'));
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
      'body', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _toxMessageIdMeta =
      const VerificationMeta('toxMessageId');
  @override
  late final GeneratedColumn<int> toxMessageId = GeneratedColumn<int>(
      'tox_message_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _deliveredMeta =
      const VerificationMeta('delivered');
  @override
  late final GeneratedColumn<bool> delivered = GeneratedColumn<bool>(
      'delivered', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("delivered" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        contactPublicKeyHex,
        outgoing,
        body,
        timestamp,
        toxMessageId,
        delivered
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('contact_public_key_hex')) {
      context.handle(
          _contactPublicKeyHexMeta,
          contactPublicKeyHex.isAcceptableOrUnknown(
              data['contact_public_key_hex']!, _contactPublicKeyHexMeta));
    } else if (isInserting) {
      context.missing(_contactPublicKeyHexMeta);
    }
    if (data.containsKey('outgoing')) {
      context.handle(_outgoingMeta,
          outgoing.isAcceptableOrUnknown(data['outgoing']!, _outgoingMeta));
    } else if (isInserting) {
      context.missing(_outgoingMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
          _bodyMeta, body.isAcceptableOrUnknown(data['body']!, _bodyMeta));
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    }
    if (data.containsKey('tox_message_id')) {
      context.handle(
          _toxMessageIdMeta,
          toxMessageId.isAcceptableOrUnknown(
              data['tox_message_id']!, _toxMessageIdMeta));
    }
    if (data.containsKey('delivered')) {
      context.handle(_deliveredMeta,
          delivered.isAcceptableOrUnknown(data['delivered']!, _deliveredMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      contactPublicKeyHex: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}contact_public_key_hex'])!,
      outgoing: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}outgoing'])!,
      body: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}body'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
      toxMessageId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tox_message_id']),
      delivered: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}delivered'])!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final int id;
  final String contactPublicKeyHex;
  final bool outgoing;
  final String body;
  final DateTime timestamp;

  /// `message_id` local do toxcore (só preenchido para mensagens enviadas
  /// por nós) — usado para casar com o read receipt e marcar [delivered].
  final int? toxMessageId;
  final bool delivered;
  const Message(
      {required this.id,
      required this.contactPublicKeyHex,
      required this.outgoing,
      required this.body,
      required this.timestamp,
      this.toxMessageId,
      required this.delivered});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['contact_public_key_hex'] = Variable<String>(contactPublicKeyHex);
    map['outgoing'] = Variable<bool>(outgoing);
    map['body'] = Variable<String>(body);
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || toxMessageId != null) {
      map['tox_message_id'] = Variable<int>(toxMessageId);
    }
    map['delivered'] = Variable<bool>(delivered);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      contactPublicKeyHex: Value(contactPublicKeyHex),
      outgoing: Value(outgoing),
      body: Value(body),
      timestamp: Value(timestamp),
      toxMessageId: toxMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(toxMessageId),
      delivered: Value(delivered),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<int>(json['id']),
      contactPublicKeyHex:
          serializer.fromJson<String>(json['contactPublicKeyHex']),
      outgoing: serializer.fromJson<bool>(json['outgoing']),
      body: serializer.fromJson<String>(json['body']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      toxMessageId: serializer.fromJson<int?>(json['toxMessageId']),
      delivered: serializer.fromJson<bool>(json['delivered']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'contactPublicKeyHex': serializer.toJson<String>(contactPublicKeyHex),
      'outgoing': serializer.toJson<bool>(outgoing),
      'body': serializer.toJson<String>(body),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'toxMessageId': serializer.toJson<int?>(toxMessageId),
      'delivered': serializer.toJson<bool>(delivered),
    };
  }

  Message copyWith(
          {int? id,
          String? contactPublicKeyHex,
          bool? outgoing,
          String? body,
          DateTime? timestamp,
          Value<int?> toxMessageId = const Value.absent(),
          bool? delivered}) =>
      Message(
        id: id ?? this.id,
        contactPublicKeyHex: contactPublicKeyHex ?? this.contactPublicKeyHex,
        outgoing: outgoing ?? this.outgoing,
        body: body ?? this.body,
        timestamp: timestamp ?? this.timestamp,
        toxMessageId:
            toxMessageId.present ? toxMessageId.value : this.toxMessageId,
        delivered: delivered ?? this.delivered,
      );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      contactPublicKeyHex: data.contactPublicKeyHex.present
          ? data.contactPublicKeyHex.value
          : this.contactPublicKeyHex,
      outgoing: data.outgoing.present ? data.outgoing.value : this.outgoing,
      body: data.body.present ? data.body.value : this.body,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      toxMessageId: data.toxMessageId.present
          ? data.toxMessageId.value
          : this.toxMessageId,
      delivered: data.delivered.present ? data.delivered.value : this.delivered,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('contactPublicKeyHex: $contactPublicKeyHex, ')
          ..write('outgoing: $outgoing, ')
          ..write('body: $body, ')
          ..write('timestamp: $timestamp, ')
          ..write('toxMessageId: $toxMessageId, ')
          ..write('delivered: $delivered')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, contactPublicKeyHex, outgoing, body,
      timestamp, toxMessageId, delivered);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.contactPublicKeyHex == this.contactPublicKeyHex &&
          other.outgoing == this.outgoing &&
          other.body == this.body &&
          other.timestamp == this.timestamp &&
          other.toxMessageId == this.toxMessageId &&
          other.delivered == this.delivered);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> id;
  final Value<String> contactPublicKeyHex;
  final Value<bool> outgoing;
  final Value<String> body;
  final Value<DateTime> timestamp;
  final Value<int?> toxMessageId;
  final Value<bool> delivered;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.contactPublicKeyHex = const Value.absent(),
    this.outgoing = const Value.absent(),
    this.body = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.toxMessageId = const Value.absent(),
    this.delivered = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.id = const Value.absent(),
    required String contactPublicKeyHex,
    required bool outgoing,
    required String body,
    this.timestamp = const Value.absent(),
    this.toxMessageId = const Value.absent(),
    this.delivered = const Value.absent(),
  })  : contactPublicKeyHex = Value(contactPublicKeyHex),
        outgoing = Value(outgoing),
        body = Value(body);
  static Insertable<Message> custom({
    Expression<int>? id,
    Expression<String>? contactPublicKeyHex,
    Expression<bool>? outgoing,
    Expression<String>? body,
    Expression<DateTime>? timestamp,
    Expression<int>? toxMessageId,
    Expression<bool>? delivered,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (contactPublicKeyHex != null)
        'contact_public_key_hex': contactPublicKeyHex,
      if (outgoing != null) 'outgoing': outgoing,
      if (body != null) 'body': body,
      if (timestamp != null) 'timestamp': timestamp,
      if (toxMessageId != null) 'tox_message_id': toxMessageId,
      if (delivered != null) 'delivered': delivered,
    });
  }

  MessagesCompanion copyWith(
      {Value<int>? id,
      Value<String>? contactPublicKeyHex,
      Value<bool>? outgoing,
      Value<String>? body,
      Value<DateTime>? timestamp,
      Value<int?>? toxMessageId,
      Value<bool>? delivered}) {
    return MessagesCompanion(
      id: id ?? this.id,
      contactPublicKeyHex: contactPublicKeyHex ?? this.contactPublicKeyHex,
      outgoing: outgoing ?? this.outgoing,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      toxMessageId: toxMessageId ?? this.toxMessageId,
      delivered: delivered ?? this.delivered,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (contactPublicKeyHex.present) {
      map['contact_public_key_hex'] =
          Variable<String>(contactPublicKeyHex.value);
    }
    if (outgoing.present) {
      map['outgoing'] = Variable<bool>(outgoing.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (toxMessageId.present) {
      map['tox_message_id'] = Variable<int>(toxMessageId.value);
    }
    if (delivered.present) {
      map['delivered'] = Variable<bool>(delivered.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('contactPublicKeyHex: $contactPublicKeyHex, ')
          ..write('outgoing: $outgoing, ')
          ..write('body: $body, ')
          ..write('timestamp: $timestamp, ')
          ..write('toxMessageId: $toxMessageId, ')
          ..write('delivered: $delivered')
          ..write(')'))
        .toString();
  }
}

class $FileTransfersTable extends FileTransfers
    with TableInfo<$FileTransfersTable, FileTransfer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FileTransfersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _contactPublicKeyHexMeta =
      const VerificationMeta('contactPublicKeyHex');
  @override
  late final GeneratedColumn<String> contactPublicKeyHex =
      GeneratedColumn<String>('contact_public_key_hex', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _toxFileNumberMeta =
      const VerificationMeta('toxFileNumber');
  @override
  late final GeneratedColumn<int> toxFileNumber = GeneratedColumn<int>(
      'tox_file_number', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _fileNameMeta =
      const VerificationMeta('fileName');
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
      'file_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _totalBytesMeta =
      const VerificationMeta('totalBytes');
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
      'total_bytes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _bytesTransferredMeta =
      const VerificationMeta('bytesTransferred');
  @override
  late final GeneratedColumn<int> bytesTransferred = GeneratedColumn<int>(
      'bytes_transferred', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _outgoingMeta =
      const VerificationMeta('outgoing');
  @override
  late final GeneratedColumn<bool> outgoing = GeneratedColumn<bool>(
      'outgoing', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("outgoing" IN (0, 1))'));
  @override
  late final GeneratedColumnWithTypeConverter<ToxFileTransferPhase, String>
      status = GeneratedColumn<String>('status', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<ToxFileTransferPhase>(
              $FileTransfersTable.$converterstatus);
  static const VerificationMeta _savedPathMeta =
      const VerificationMeta('savedPath');
  @override
  late final GeneratedColumn<String> savedPath = GeneratedColumn<String>(
      'saved_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        contactPublicKeyHex,
        toxFileNumber,
        fileName,
        totalBytes,
        bytesTransferred,
        outgoing,
        status,
        savedPath,
        timestamp
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_transfers';
  @override
  VerificationContext validateIntegrity(Insertable<FileTransfer> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('contact_public_key_hex')) {
      context.handle(
          _contactPublicKeyHexMeta,
          contactPublicKeyHex.isAcceptableOrUnknown(
              data['contact_public_key_hex']!, _contactPublicKeyHexMeta));
    } else if (isInserting) {
      context.missing(_contactPublicKeyHexMeta);
    }
    if (data.containsKey('tox_file_number')) {
      context.handle(
          _toxFileNumberMeta,
          toxFileNumber.isAcceptableOrUnknown(
              data['tox_file_number']!, _toxFileNumberMeta));
    } else if (isInserting) {
      context.missing(_toxFileNumberMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(_fileNameMeta,
          fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta));
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
          _totalBytesMeta,
          totalBytes.isAcceptableOrUnknown(
              data['total_bytes']!, _totalBytesMeta));
    } else if (isInserting) {
      context.missing(_totalBytesMeta);
    }
    if (data.containsKey('bytes_transferred')) {
      context.handle(
          _bytesTransferredMeta,
          bytesTransferred.isAcceptableOrUnknown(
              data['bytes_transferred']!, _bytesTransferredMeta));
    }
    if (data.containsKey('outgoing')) {
      context.handle(_outgoingMeta,
          outgoing.isAcceptableOrUnknown(data['outgoing']!, _outgoingMeta));
    } else if (isInserting) {
      context.missing(_outgoingMeta);
    }
    if (data.containsKey('saved_path')) {
      context.handle(_savedPathMeta,
          savedPath.isAcceptableOrUnknown(data['saved_path']!, _savedPathMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FileTransfer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FileTransfer(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      contactPublicKeyHex: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}contact_public_key_hex'])!,
      toxFileNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}tox_file_number'])!,
      fileName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_name'])!,
      totalBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_bytes'])!,
      bytesTransferred: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bytes_transferred'])!,
      outgoing: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}outgoing'])!,
      status: $FileTransfersTable.$converterstatus.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!),
      savedPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}saved_path']),
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
    );
  }

  @override
  $FileTransfersTable createAlias(String alias) {
    return $FileTransfersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ToxFileTransferPhase, String, String>
      $converterstatus = const EnumNameConverter<ToxFileTransferPhase>(
          ToxFileTransferPhase.values);
}

class FileTransfer extends DataClass implements Insertable<FileTransfer> {
  final int id;
  final String contactPublicKeyHex;
  final int toxFileNumber;
  final String fileName;
  final int totalBytes;
  final int bytesTransferred;
  final bool outgoing;
  final ToxFileTransferPhase status;
  final String? savedPath;
  final DateTime timestamp;
  const FileTransfer(
      {required this.id,
      required this.contactPublicKeyHex,
      required this.toxFileNumber,
      required this.fileName,
      required this.totalBytes,
      required this.bytesTransferred,
      required this.outgoing,
      required this.status,
      this.savedPath,
      required this.timestamp});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['contact_public_key_hex'] = Variable<String>(contactPublicKeyHex);
    map['tox_file_number'] = Variable<int>(toxFileNumber);
    map['file_name'] = Variable<String>(fileName);
    map['total_bytes'] = Variable<int>(totalBytes);
    map['bytes_transferred'] = Variable<int>(bytesTransferred);
    map['outgoing'] = Variable<bool>(outgoing);
    {
      map['status'] =
          Variable<String>($FileTransfersTable.$converterstatus.toSql(status));
    }
    if (!nullToAbsent || savedPath != null) {
      map['saved_path'] = Variable<String>(savedPath);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  FileTransfersCompanion toCompanion(bool nullToAbsent) {
    return FileTransfersCompanion(
      id: Value(id),
      contactPublicKeyHex: Value(contactPublicKeyHex),
      toxFileNumber: Value(toxFileNumber),
      fileName: Value(fileName),
      totalBytes: Value(totalBytes),
      bytesTransferred: Value(bytesTransferred),
      outgoing: Value(outgoing),
      status: Value(status),
      savedPath: savedPath == null && nullToAbsent
          ? const Value.absent()
          : Value(savedPath),
      timestamp: Value(timestamp),
    );
  }

  factory FileTransfer.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FileTransfer(
      id: serializer.fromJson<int>(json['id']),
      contactPublicKeyHex:
          serializer.fromJson<String>(json['contactPublicKeyHex']),
      toxFileNumber: serializer.fromJson<int>(json['toxFileNumber']),
      fileName: serializer.fromJson<String>(json['fileName']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
      bytesTransferred: serializer.fromJson<int>(json['bytesTransferred']),
      outgoing: serializer.fromJson<bool>(json['outgoing']),
      status: $FileTransfersTable.$converterstatus
          .fromJson(serializer.fromJson<String>(json['status'])),
      savedPath: serializer.fromJson<String?>(json['savedPath']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'contactPublicKeyHex': serializer.toJson<String>(contactPublicKeyHex),
      'toxFileNumber': serializer.toJson<int>(toxFileNumber),
      'fileName': serializer.toJson<String>(fileName),
      'totalBytes': serializer.toJson<int>(totalBytes),
      'bytesTransferred': serializer.toJson<int>(bytesTransferred),
      'outgoing': serializer.toJson<bool>(outgoing),
      'status': serializer
          .toJson<String>($FileTransfersTable.$converterstatus.toJson(status)),
      'savedPath': serializer.toJson<String?>(savedPath),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  FileTransfer copyWith(
          {int? id,
          String? contactPublicKeyHex,
          int? toxFileNumber,
          String? fileName,
          int? totalBytes,
          int? bytesTransferred,
          bool? outgoing,
          ToxFileTransferPhase? status,
          Value<String?> savedPath = const Value.absent(),
          DateTime? timestamp}) =>
      FileTransfer(
        id: id ?? this.id,
        contactPublicKeyHex: contactPublicKeyHex ?? this.contactPublicKeyHex,
        toxFileNumber: toxFileNumber ?? this.toxFileNumber,
        fileName: fileName ?? this.fileName,
        totalBytes: totalBytes ?? this.totalBytes,
        bytesTransferred: bytesTransferred ?? this.bytesTransferred,
        outgoing: outgoing ?? this.outgoing,
        status: status ?? this.status,
        savedPath: savedPath.present ? savedPath.value : this.savedPath,
        timestamp: timestamp ?? this.timestamp,
      );
  FileTransfer copyWithCompanion(FileTransfersCompanion data) {
    return FileTransfer(
      id: data.id.present ? data.id.value : this.id,
      contactPublicKeyHex: data.contactPublicKeyHex.present
          ? data.contactPublicKeyHex.value
          : this.contactPublicKeyHex,
      toxFileNumber: data.toxFileNumber.present
          ? data.toxFileNumber.value
          : this.toxFileNumber,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      totalBytes:
          data.totalBytes.present ? data.totalBytes.value : this.totalBytes,
      bytesTransferred: data.bytesTransferred.present
          ? data.bytesTransferred.value
          : this.bytesTransferred,
      outgoing: data.outgoing.present ? data.outgoing.value : this.outgoing,
      status: data.status.present ? data.status.value : this.status,
      savedPath: data.savedPath.present ? data.savedPath.value : this.savedPath,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FileTransfer(')
          ..write('id: $id, ')
          ..write('contactPublicKeyHex: $contactPublicKeyHex, ')
          ..write('toxFileNumber: $toxFileNumber, ')
          ..write('fileName: $fileName, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('bytesTransferred: $bytesTransferred, ')
          ..write('outgoing: $outgoing, ')
          ..write('status: $status, ')
          ..write('savedPath: $savedPath, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      contactPublicKeyHex,
      toxFileNumber,
      fileName,
      totalBytes,
      bytesTransferred,
      outgoing,
      status,
      savedPath,
      timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileTransfer &&
          other.id == this.id &&
          other.contactPublicKeyHex == this.contactPublicKeyHex &&
          other.toxFileNumber == this.toxFileNumber &&
          other.fileName == this.fileName &&
          other.totalBytes == this.totalBytes &&
          other.bytesTransferred == this.bytesTransferred &&
          other.outgoing == this.outgoing &&
          other.status == this.status &&
          other.savedPath == this.savedPath &&
          other.timestamp == this.timestamp);
}

class FileTransfersCompanion extends UpdateCompanion<FileTransfer> {
  final Value<int> id;
  final Value<String> contactPublicKeyHex;
  final Value<int> toxFileNumber;
  final Value<String> fileName;
  final Value<int> totalBytes;
  final Value<int> bytesTransferred;
  final Value<bool> outgoing;
  final Value<ToxFileTransferPhase> status;
  final Value<String?> savedPath;
  final Value<DateTime> timestamp;
  const FileTransfersCompanion({
    this.id = const Value.absent(),
    this.contactPublicKeyHex = const Value.absent(),
    this.toxFileNumber = const Value.absent(),
    this.fileName = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.bytesTransferred = const Value.absent(),
    this.outgoing = const Value.absent(),
    this.status = const Value.absent(),
    this.savedPath = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  FileTransfersCompanion.insert({
    this.id = const Value.absent(),
    required String contactPublicKeyHex,
    required int toxFileNumber,
    required String fileName,
    required int totalBytes,
    this.bytesTransferred = const Value.absent(),
    required bool outgoing,
    required ToxFileTransferPhase status,
    this.savedPath = const Value.absent(),
    this.timestamp = const Value.absent(),
  })  : contactPublicKeyHex = Value(contactPublicKeyHex),
        toxFileNumber = Value(toxFileNumber),
        fileName = Value(fileName),
        totalBytes = Value(totalBytes),
        outgoing = Value(outgoing),
        status = Value(status);
  static Insertable<FileTransfer> custom({
    Expression<int>? id,
    Expression<String>? contactPublicKeyHex,
    Expression<int>? toxFileNumber,
    Expression<String>? fileName,
    Expression<int>? totalBytes,
    Expression<int>? bytesTransferred,
    Expression<bool>? outgoing,
    Expression<String>? status,
    Expression<String>? savedPath,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (contactPublicKeyHex != null)
        'contact_public_key_hex': contactPublicKeyHex,
      if (toxFileNumber != null) 'tox_file_number': toxFileNumber,
      if (fileName != null) 'file_name': fileName,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (bytesTransferred != null) 'bytes_transferred': bytesTransferred,
      if (outgoing != null) 'outgoing': outgoing,
      if (status != null) 'status': status,
      if (savedPath != null) 'saved_path': savedPath,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  FileTransfersCompanion copyWith(
      {Value<int>? id,
      Value<String>? contactPublicKeyHex,
      Value<int>? toxFileNumber,
      Value<String>? fileName,
      Value<int>? totalBytes,
      Value<int>? bytesTransferred,
      Value<bool>? outgoing,
      Value<ToxFileTransferPhase>? status,
      Value<String?>? savedPath,
      Value<DateTime>? timestamp}) {
    return FileTransfersCompanion(
      id: id ?? this.id,
      contactPublicKeyHex: contactPublicKeyHex ?? this.contactPublicKeyHex,
      toxFileNumber: toxFileNumber ?? this.toxFileNumber,
      fileName: fileName ?? this.fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      outgoing: outgoing ?? this.outgoing,
      status: status ?? this.status,
      savedPath: savedPath ?? this.savedPath,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (contactPublicKeyHex.present) {
      map['contact_public_key_hex'] =
          Variable<String>(contactPublicKeyHex.value);
    }
    if (toxFileNumber.present) {
      map['tox_file_number'] = Variable<int>(toxFileNumber.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (bytesTransferred.present) {
      map['bytes_transferred'] = Variable<int>(bytesTransferred.value);
    }
    if (outgoing.present) {
      map['outgoing'] = Variable<bool>(outgoing.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
          $FileTransfersTable.$converterstatus.toSql(status.value));
    }
    if (savedPath.present) {
      map['saved_path'] = Variable<String>(savedPath.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FileTransfersCompanion(')
          ..write('id: $id, ')
          ..write('contactPublicKeyHex: $contactPublicKeyHex, ')
          ..write('toxFileNumber: $toxFileNumber, ')
          ..write('fileName: $fileName, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('bytesTransferred: $bytesTransferred, ')
          ..write('outgoing: $outgoing, ')
          ..write('status: $status, ')
          ..write('savedPath: $savedPath, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ContactsTable contacts = $ContactsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $FileTransfersTable fileTransfers = $FileTransfersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [contacts, messages, fileTransfers];
}

typedef $$ContactsTableCreateCompanionBuilder = ContactsCompanion Function({
  Value<int> id,
  required String publicKeyHex,
  Value<String?> nickname,
  Value<DateTime> addedAt,
});
typedef $$ContactsTableUpdateCompanionBuilder = ContactsCompanion Function({
  Value<int> id,
  Value<String> publicKeyHex,
  Value<String?> nickname,
  Value<DateTime> addedAt,
});

class $$ContactsTableFilterComposer
    extends Composer<_$AppDatabase, $ContactsTable> {
  $$ContactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get publicKeyHex => $composableBuilder(
      column: $table.publicKeyHex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get nickname => $composableBuilder(
      column: $table.nickname, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));
}

class $$ContactsTableOrderingComposer
    extends Composer<_$AppDatabase, $ContactsTable> {
  $$ContactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get publicKeyHex => $composableBuilder(
      column: $table.publicKeyHex,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get nickname => $composableBuilder(
      column: $table.nickname, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$ContactsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ContactsTable> {
  $$ContactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get publicKeyHex => $composableBuilder(
      column: $table.publicKeyHex, builder: (column) => column);

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$ContactsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ContactsTable,
    Contact,
    $$ContactsTableFilterComposer,
    $$ContactsTableOrderingComposer,
    $$ContactsTableAnnotationComposer,
    $$ContactsTableCreateCompanionBuilder,
    $$ContactsTableUpdateCompanionBuilder,
    (Contact, BaseReferences<_$AppDatabase, $ContactsTable, Contact>),
    Contact,
    PrefetchHooks Function()> {
  $$ContactsTableTableManager(_$AppDatabase db, $ContactsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> publicKeyHex = const Value.absent(),
            Value<String?> nickname = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
          }) =>
              ContactsCompanion(
            id: id,
            publicKeyHex: publicKeyHex,
            nickname: nickname,
            addedAt: addedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String publicKeyHex,
            Value<String?> nickname = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
          }) =>
              ContactsCompanion.insert(
            id: id,
            publicKeyHex: publicKeyHex,
            nickname: nickname,
            addedAt: addedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ContactsTable, Contact>(table),
                    BaseReferences<_$AppDatabase, $ContactsTable, Contact>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ContactsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ContactsTable,
    Contact,
    $$ContactsTableFilterComposer,
    $$ContactsTableOrderingComposer,
    $$ContactsTableAnnotationComposer,
    $$ContactsTableCreateCompanionBuilder,
    $$ContactsTableUpdateCompanionBuilder,
    (Contact, BaseReferences<_$AppDatabase, $ContactsTable, Contact>),
    Contact,
    PrefetchHooks Function()>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  required String contactPublicKeyHex,
  required bool outgoing,
  required String body,
  Value<DateTime> timestamp,
  Value<int?> toxMessageId,
  Value<bool> delivered,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  Value<String> contactPublicKeyHex,
  Value<bool> outgoing,
  Value<String> body,
  Value<DateTime> timestamp,
  Value<int?> toxMessageId,
  Value<bool> delivered,
});

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contactPublicKeyHex => $composableBuilder(
      column: $table.contactPublicKeyHex,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get outgoing => $composableBuilder(
      column: $table.outgoing, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get toxMessageId => $composableBuilder(
      column: $table.toxMessageId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get delivered => $composableBuilder(
      column: $table.delivered, builder: (column) => ColumnFilters(column));
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contactPublicKeyHex => $composableBuilder(
      column: $table.contactPublicKeyHex,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get outgoing => $composableBuilder(
      column: $table.outgoing, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get toxMessageId => $composableBuilder(
      column: $table.toxMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get delivered => $composableBuilder(
      column: $table.delivered, builder: (column) => ColumnOrderings(column));
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get contactPublicKeyHex => $composableBuilder(
      column: $table.contactPublicKeyHex, builder: (column) => column);

  GeneratedColumn<bool> get outgoing =>
      $composableBuilder(column: $table.outgoing, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get toxMessageId => $composableBuilder(
      column: $table.toxMessageId, builder: (column) => column);

  GeneratedColumn<bool> get delivered =>
      $composableBuilder(column: $table.delivered, builder: (column) => column);
}

class $$MessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()> {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> contactPublicKeyHex = const Value.absent(),
            Value<bool> outgoing = const Value.absent(),
            Value<String> body = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
            Value<int?> toxMessageId = const Value.absent(),
            Value<bool> delivered = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            contactPublicKeyHex: contactPublicKeyHex,
            outgoing: outgoing,
            body: body,
            timestamp: timestamp,
            toxMessageId: toxMessageId,
            delivered: delivered,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String contactPublicKeyHex,
            required bool outgoing,
            required String body,
            Value<DateTime> timestamp = const Value.absent(),
            Value<int?> toxMessageId = const Value.absent(),
            Value<bool> delivered = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            id: id,
            contactPublicKeyHex: contactPublicKeyHex,
            outgoing: outgoing,
            body: body,
            timestamp: timestamp,
            toxMessageId: toxMessageId,
            delivered: delivered,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$MessagesTable, Message>(table),
                    BaseReferences<_$AppDatabase, $MessagesTable, Message>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()>;
typedef $$FileTransfersTableCreateCompanionBuilder = FileTransfersCompanion
    Function({
  Value<int> id,
  required String contactPublicKeyHex,
  required int toxFileNumber,
  required String fileName,
  required int totalBytes,
  Value<int> bytesTransferred,
  required bool outgoing,
  required ToxFileTransferPhase status,
  Value<String?> savedPath,
  Value<DateTime> timestamp,
});
typedef $$FileTransfersTableUpdateCompanionBuilder = FileTransfersCompanion
    Function({
  Value<int> id,
  Value<String> contactPublicKeyHex,
  Value<int> toxFileNumber,
  Value<String> fileName,
  Value<int> totalBytes,
  Value<int> bytesTransferred,
  Value<bool> outgoing,
  Value<ToxFileTransferPhase> status,
  Value<String?> savedPath,
  Value<DateTime> timestamp,
});

class $$FileTransfersTableFilterComposer
    extends Composer<_$AppDatabase, $FileTransfersTable> {
  $$FileTransfersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contactPublicKeyHex => $composableBuilder(
      column: $table.contactPublicKeyHex,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get toxFileNumber => $composableBuilder(
      column: $table.toxFileNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalBytes => $composableBuilder(
      column: $table.totalBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get bytesTransferred => $composableBuilder(
      column: $table.bytesTransferred,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get outgoing => $composableBuilder(
      column: $table.outgoing, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<ToxFileTransferPhase, ToxFileTransferPhase,
          String>
      get status => $composableBuilder(
          column: $table.status,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get savedPath => $composableBuilder(
      column: $table.savedPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));
}

class $$FileTransfersTableOrderingComposer
    extends Composer<_$AppDatabase, $FileTransfersTable> {
  $$FileTransfersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contactPublicKeyHex => $composableBuilder(
      column: $table.contactPublicKeyHex,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get toxFileNumber => $composableBuilder(
      column: $table.toxFileNumber,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalBytes => $composableBuilder(
      column: $table.totalBytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bytesTransferred => $composableBuilder(
      column: $table.bytesTransferred,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get outgoing => $composableBuilder(
      column: $table.outgoing, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get savedPath => $composableBuilder(
      column: $table.savedPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));
}

class $$FileTransfersTableAnnotationComposer
    extends Composer<_$AppDatabase, $FileTransfersTable> {
  $$FileTransfersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get contactPublicKeyHex => $composableBuilder(
      column: $table.contactPublicKeyHex, builder: (column) => column);

  GeneratedColumn<int> get toxFileNumber => $composableBuilder(
      column: $table.toxFileNumber, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get totalBytes => $composableBuilder(
      column: $table.totalBytes, builder: (column) => column);

  GeneratedColumn<int> get bytesTransferred => $composableBuilder(
      column: $table.bytesTransferred, builder: (column) => column);

  GeneratedColumn<bool> get outgoing =>
      $composableBuilder(column: $table.outgoing, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ToxFileTransferPhase, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get savedPath =>
      $composableBuilder(column: $table.savedPath, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $$FileTransfersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FileTransfersTable,
    FileTransfer,
    $$FileTransfersTableFilterComposer,
    $$FileTransfersTableOrderingComposer,
    $$FileTransfersTableAnnotationComposer,
    $$FileTransfersTableCreateCompanionBuilder,
    $$FileTransfersTableUpdateCompanionBuilder,
    (
      FileTransfer,
      BaseReferences<_$AppDatabase, $FileTransfersTable, FileTransfer>
    ),
    FileTransfer,
    PrefetchHooks Function()> {
  $$FileTransfersTableTableManager(_$AppDatabase db, $FileTransfersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FileTransfersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FileTransfersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FileTransfersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> contactPublicKeyHex = const Value.absent(),
            Value<int> toxFileNumber = const Value.absent(),
            Value<String> fileName = const Value.absent(),
            Value<int> totalBytes = const Value.absent(),
            Value<int> bytesTransferred = const Value.absent(),
            Value<bool> outgoing = const Value.absent(),
            Value<ToxFileTransferPhase> status = const Value.absent(),
            Value<String?> savedPath = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
          }) =>
              FileTransfersCompanion(
            id: id,
            contactPublicKeyHex: contactPublicKeyHex,
            toxFileNumber: toxFileNumber,
            fileName: fileName,
            totalBytes: totalBytes,
            bytesTransferred: bytesTransferred,
            outgoing: outgoing,
            status: status,
            savedPath: savedPath,
            timestamp: timestamp,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String contactPublicKeyHex,
            required int toxFileNumber,
            required String fileName,
            required int totalBytes,
            Value<int> bytesTransferred = const Value.absent(),
            required bool outgoing,
            required ToxFileTransferPhase status,
            Value<String?> savedPath = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
          }) =>
              FileTransfersCompanion.insert(
            id: id,
            contactPublicKeyHex: contactPublicKeyHex,
            toxFileNumber: toxFileNumber,
            fileName: fileName,
            totalBytes: totalBytes,
            bytesTransferred: bytesTransferred,
            outgoing: outgoing,
            status: status,
            savedPath: savedPath,
            timestamp: timestamp,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$FileTransfersTable, FileTransfer>(table),
                    BaseReferences<_$AppDatabase, $FileTransfersTable,
                        FileTransfer>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$FileTransfersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $FileTransfersTable,
    FileTransfer,
    $$FileTransfersTableFilterComposer,
    $$FileTransfersTableOrderingComposer,
    $$FileTransfersTableAnnotationComposer,
    $$FileTransfersTableCreateCompanionBuilder,
    $$FileTransfersTableUpdateCompanionBuilder,
    (
      FileTransfer,
      BaseReferences<_$AppDatabase, $FileTransfersTable, FileTransfer>
    ),
    FileTransfer,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ContactsTableTableManager get contacts =>
      $$ContactsTableTableManager(_db, _db.contacts);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$FileTransfersTableTableManager get fileTransfers =>
      $$FileTransfersTableTableManager(_db, _db.fileTransfers);
}
