package com.timlorne.wiringpro.data.db;

import android.database.Cursor;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.collection.ArrayMap;
import androidx.room.CoroutinesRoom;
import androidx.room.EntityDeletionOrUpdateAdapter;
import androidx.room.EntityInsertionAdapter;
import androidx.room.RoomDatabase;
import androidx.room.RoomSQLiteQuery;
import androidx.room.SharedSQLiteStatement;
import androidx.room.util.CursorUtil;
import androidx.room.util.DBUtil;
import androidx.room.util.RelationUtil;
import androidx.room.util.StringUtil;
import androidx.sqlite.db.SupportSQLiteStatement;
import java.lang.Class;
import java.lang.Exception;
import java.lang.Integer;
import java.lang.Object;
import java.lang.Override;
import java.lang.String;
import java.lang.StringBuilder;
import java.lang.SuppressWarnings;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.concurrent.Callable;
import javax.annotation.processing.Generated;
import kotlin.Unit;
import kotlin.coroutines.Continuation;
import kotlinx.coroutines.flow.Flow;

@Generated("androidx.room.RoomProcessor")
@SuppressWarnings({"unchecked", "deprecation"})
public final class ConnectorDao_Impl implements ConnectorDao {
  private final RoomDatabase __db;

  private final EntityInsertionAdapter<ConnectorEntity> __insertionAdapterOfConnectorEntity;

  private final Converters __converters = new Converters();

  private final EntityDeletionOrUpdateAdapter<ConnectorEntity> __deletionAdapterOfConnectorEntity;

  private final SharedSQLiteStatement __preparedStmtOfDeleteById;

  public ConnectorDao_Impl(@NonNull final RoomDatabase __db) {
    this.__db = __db;
    this.__insertionAdapterOfConnectorEntity = new EntityInsertionAdapter<ConnectorEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT OR REPLACE INTO `connectors` (`id`,`projectId`,`label`,`rows`,`partRef`) VALUES (?,?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final ConnectorEntity entity) {
        statement.bindString(1, entity.getId());
        statement.bindString(2, entity.getProjectId());
        statement.bindString(3, entity.getLabel());
        final String _tmp = __converters.fromRows(entity.getRows());
        statement.bindString(4, _tmp);
        if (entity.getPartRef() == null) {
          statement.bindNull(5);
        } else {
          statement.bindString(5, entity.getPartRef());
        }
      }
    };
    this.__deletionAdapterOfConnectorEntity = new EntityDeletionOrUpdateAdapter<ConnectorEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "DELETE FROM `connectors` WHERE `id` = ?";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final ConnectorEntity entity) {
        statement.bindString(1, entity.getId());
      }
    };
    this.__preparedStmtOfDeleteById = new SharedSQLiteStatement(__db) {
      @Override
      @NonNull
      public String createQuery() {
        final String _query = "DELETE FROM connectors WHERE id = ?";
        return _query;
      }
    };
  }

  @Override
  public Object upsert(final ConnectorEntity connector,
      final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        __db.beginTransaction();
        try {
          __insertionAdapterOfConnectorEntity.insert(connector);
          __db.setTransactionSuccessful();
          return Unit.INSTANCE;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Object delete(final ConnectorEntity connector,
      final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        __db.beginTransaction();
        try {
          __deletionAdapterOfConnectorEntity.handle(connector);
          __db.setTransactionSuccessful();
          return Unit.INSTANCE;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Object deleteById(final String connectorId, final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        final SupportSQLiteStatement _stmt = __preparedStmtOfDeleteById.acquire();
        int _argIndex = 1;
        _stmt.bindString(_argIndex, connectorId);
        try {
          __db.beginTransaction();
          try {
            _stmt.executeUpdateDelete();
            __db.setTransactionSuccessful();
            return Unit.INSTANCE;
          } finally {
            __db.endTransaction();
          }
        } finally {
          __preparedStmtOfDeleteById.release(_stmt);
        }
      }
    }, $completion);
  }

  @Override
  public Flow<List<ConnectorEntity>> observeForProject(final String projectId) {
    final String _sql = "SELECT * FROM connectors WHERE projectId = ?";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindString(_argIndex, projectId);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"connectors"}, new Callable<List<ConnectorEntity>>() {
      @Override
      @NonNull
      public List<ConnectorEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfProjectId = CursorUtil.getColumnIndexOrThrow(_cursor, "projectId");
          final int _cursorIndexOfLabel = CursorUtil.getColumnIndexOrThrow(_cursor, "label");
          final int _cursorIndexOfRows = CursorUtil.getColumnIndexOrThrow(_cursor, "rows");
          final int _cursorIndexOfPartRef = CursorUtil.getColumnIndexOrThrow(_cursor, "partRef");
          final List<ConnectorEntity> _result = new ArrayList<ConnectorEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final ConnectorEntity _item;
            final String _tmpId;
            _tmpId = _cursor.getString(_cursorIndexOfId);
            final String _tmpProjectId;
            _tmpProjectId = _cursor.getString(_cursorIndexOfProjectId);
            final String _tmpLabel;
            _tmpLabel = _cursor.getString(_cursorIndexOfLabel);
            final List<Integer> _tmpRows;
            final String _tmp;
            _tmp = _cursor.getString(_cursorIndexOfRows);
            _tmpRows = __converters.toRows(_tmp);
            final String _tmpPartRef;
            if (_cursor.isNull(_cursorIndexOfPartRef)) {
              _tmpPartRef = null;
            } else {
              _tmpPartRef = _cursor.getString(_cursorIndexOfPartRef);
            }
            _item = new ConnectorEntity(_tmpId,_tmpProjectId,_tmpLabel,_tmpRows,_tmpPartRef);
            _result.add(_item);
          }
          return _result;
        } finally {
          _cursor.close();
        }
      }

      @Override
      protected void finalize() {
        _statement.release();
      }
    });
  }

  @Override
  public Flow<List<ConnectorWithPins>> observeWithPinsForProject(final String projectId) {
    final String _sql = "SELECT * FROM connectors WHERE projectId = ?";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindString(_argIndex, projectId);
    return CoroutinesRoom.createFlow(__db, true, new String[] {"pins",
        "connectors"}, new Callable<List<ConnectorWithPins>>() {
      @Override
      @NonNull
      public List<ConnectorWithPins> call() throws Exception {
        __db.beginTransaction();
        try {
          final Cursor _cursor = DBUtil.query(__db, _statement, true, null);
          try {
            final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
            final int _cursorIndexOfProjectId = CursorUtil.getColumnIndexOrThrow(_cursor, "projectId");
            final int _cursorIndexOfLabel = CursorUtil.getColumnIndexOrThrow(_cursor, "label");
            final int _cursorIndexOfRows = CursorUtil.getColumnIndexOrThrow(_cursor, "rows");
            final int _cursorIndexOfPartRef = CursorUtil.getColumnIndexOrThrow(_cursor, "partRef");
            final ArrayMap<String, ArrayList<PinEntity>> _collectionPins = new ArrayMap<String, ArrayList<PinEntity>>();
            while (_cursor.moveToNext()) {
              final String _tmpKey;
              _tmpKey = _cursor.getString(_cursorIndexOfId);
              if (!_collectionPins.containsKey(_tmpKey)) {
                _collectionPins.put(_tmpKey, new ArrayList<PinEntity>());
              }
            }
            _cursor.moveToPosition(-1);
            __fetchRelationshippinsAscomTimlorneWiringproDataDbPinEntity(_collectionPins);
            final List<ConnectorWithPins> _result = new ArrayList<ConnectorWithPins>(_cursor.getCount());
            while (_cursor.moveToNext()) {
              final ConnectorWithPins _item;
              final ConnectorEntity _tmpConnector;
              final String _tmpId;
              _tmpId = _cursor.getString(_cursorIndexOfId);
              final String _tmpProjectId;
              _tmpProjectId = _cursor.getString(_cursorIndexOfProjectId);
              final String _tmpLabel;
              _tmpLabel = _cursor.getString(_cursorIndexOfLabel);
              final List<Integer> _tmpRows;
              final String _tmp;
              _tmp = _cursor.getString(_cursorIndexOfRows);
              _tmpRows = __converters.toRows(_tmp);
              final String _tmpPartRef;
              if (_cursor.isNull(_cursorIndexOfPartRef)) {
                _tmpPartRef = null;
              } else {
                _tmpPartRef = _cursor.getString(_cursorIndexOfPartRef);
              }
              _tmpConnector = new ConnectorEntity(_tmpId,_tmpProjectId,_tmpLabel,_tmpRows,_tmpPartRef);
              final ArrayList<PinEntity> _tmpPinsCollection;
              final String _tmpKey_1;
              _tmpKey_1 = _cursor.getString(_cursorIndexOfId);
              _tmpPinsCollection = _collectionPins.get(_tmpKey_1);
              _item = new ConnectorWithPins(_tmpConnector,_tmpPinsCollection);
              _result.add(_item);
            }
            __db.setTransactionSuccessful();
            return _result;
          } finally {
            _cursor.close();
          }
        } finally {
          __db.endTransaction();
        }
      }

      @Override
      protected void finalize() {
        _statement.release();
      }
    });
  }

  @Override
  public Flow<ConnectorWithPins> observeWithPins(final String connectorId) {
    final String _sql = "SELECT * FROM connectors WHERE id = ?";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindString(_argIndex, connectorId);
    return CoroutinesRoom.createFlow(__db, true, new String[] {"pins",
        "connectors"}, new Callable<ConnectorWithPins>() {
      @Override
      @Nullable
      public ConnectorWithPins call() throws Exception {
        __db.beginTransaction();
        try {
          final Cursor _cursor = DBUtil.query(__db, _statement, true, null);
          try {
            final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
            final int _cursorIndexOfProjectId = CursorUtil.getColumnIndexOrThrow(_cursor, "projectId");
            final int _cursorIndexOfLabel = CursorUtil.getColumnIndexOrThrow(_cursor, "label");
            final int _cursorIndexOfRows = CursorUtil.getColumnIndexOrThrow(_cursor, "rows");
            final int _cursorIndexOfPartRef = CursorUtil.getColumnIndexOrThrow(_cursor, "partRef");
            final ArrayMap<String, ArrayList<PinEntity>> _collectionPins = new ArrayMap<String, ArrayList<PinEntity>>();
            while (_cursor.moveToNext()) {
              final String _tmpKey;
              _tmpKey = _cursor.getString(_cursorIndexOfId);
              if (!_collectionPins.containsKey(_tmpKey)) {
                _collectionPins.put(_tmpKey, new ArrayList<PinEntity>());
              }
            }
            _cursor.moveToPosition(-1);
            __fetchRelationshippinsAscomTimlorneWiringproDataDbPinEntity(_collectionPins);
            final ConnectorWithPins _result;
            if (_cursor.moveToFirst()) {
              final ConnectorEntity _tmpConnector;
              final String _tmpId;
              _tmpId = _cursor.getString(_cursorIndexOfId);
              final String _tmpProjectId;
              _tmpProjectId = _cursor.getString(_cursorIndexOfProjectId);
              final String _tmpLabel;
              _tmpLabel = _cursor.getString(_cursorIndexOfLabel);
              final List<Integer> _tmpRows;
              final String _tmp;
              _tmp = _cursor.getString(_cursorIndexOfRows);
              _tmpRows = __converters.toRows(_tmp);
              final String _tmpPartRef;
              if (_cursor.isNull(_cursorIndexOfPartRef)) {
                _tmpPartRef = null;
              } else {
                _tmpPartRef = _cursor.getString(_cursorIndexOfPartRef);
              }
              _tmpConnector = new ConnectorEntity(_tmpId,_tmpProjectId,_tmpLabel,_tmpRows,_tmpPartRef);
              final ArrayList<PinEntity> _tmpPinsCollection;
              final String _tmpKey_1;
              _tmpKey_1 = _cursor.getString(_cursorIndexOfId);
              _tmpPinsCollection = _collectionPins.get(_tmpKey_1);
              _result = new ConnectorWithPins(_tmpConnector,_tmpPinsCollection);
            } else {
              _result = null;
            }
            __db.setTransactionSuccessful();
            return _result;
          } finally {
            _cursor.close();
          }
        } finally {
          __db.endTransaction();
        }
      }

      @Override
      protected void finalize() {
        _statement.release();
      }
    });
  }

  @NonNull
  public static List<Class<?>> getRequiredConverters() {
    return Collections.emptyList();
  }

  private void __fetchRelationshippinsAscomTimlorneWiringproDataDbPinEntity(
      @NonNull final ArrayMap<String, ArrayList<PinEntity>> _map) {
    final Set<String> __mapKeySet = _map.keySet();
    if (__mapKeySet.isEmpty()) {
      return;
    }
    if (_map.size() > RoomDatabase.MAX_BIND_PARAMETER_CNT) {
      RelationUtil.recursiveFetchArrayMap(_map, true, (map) -> {
        __fetchRelationshippinsAscomTimlorneWiringproDataDbPinEntity(map);
        return Unit.INSTANCE;
      });
      return;
    }
    final StringBuilder _stringBuilder = StringUtil.newStringBuilder();
    _stringBuilder.append("SELECT `id`,`connectorId`,`index`,`row`,`col`,`netId`,`label` FROM `pins` WHERE `connectorId` IN (");
    final int _inputSize = __mapKeySet.size();
    StringUtil.appendPlaceholders(_stringBuilder, _inputSize);
    _stringBuilder.append(")");
    final String _sql = _stringBuilder.toString();
    final int _argCount = 0 + _inputSize;
    final RoomSQLiteQuery _stmt = RoomSQLiteQuery.acquire(_sql, _argCount);
    int _argIndex = 1;
    for (String _item : __mapKeySet) {
      _stmt.bindString(_argIndex, _item);
      _argIndex++;
    }
    final Cursor _cursor = DBUtil.query(__db, _stmt, false, null);
    try {
      final int _itemKeyIndex = CursorUtil.getColumnIndex(_cursor, "connectorId");
      if (_itemKeyIndex == -1) {
        return;
      }
      final int _cursorIndexOfId = 0;
      final int _cursorIndexOfConnectorId = 1;
      final int _cursorIndexOfIndex = 2;
      final int _cursorIndexOfRow = 3;
      final int _cursorIndexOfCol = 4;
      final int _cursorIndexOfNetId = 5;
      final int _cursorIndexOfLabel = 6;
      while (_cursor.moveToNext()) {
        final String _tmpKey;
        _tmpKey = _cursor.getString(_itemKeyIndex);
        final ArrayList<PinEntity> _tmpRelation = _map.get(_tmpKey);
        if (_tmpRelation != null) {
          final PinEntity _item_1;
          final String _tmpId;
          _tmpId = _cursor.getString(_cursorIndexOfId);
          final String _tmpConnectorId;
          _tmpConnectorId = _cursor.getString(_cursorIndexOfConnectorId);
          final int _tmpIndex;
          _tmpIndex = _cursor.getInt(_cursorIndexOfIndex);
          final int _tmpRow;
          _tmpRow = _cursor.getInt(_cursorIndexOfRow);
          final int _tmpCol;
          _tmpCol = _cursor.getInt(_cursorIndexOfCol);
          final String _tmpNetId;
          if (_cursor.isNull(_cursorIndexOfNetId)) {
            _tmpNetId = null;
          } else {
            _tmpNetId = _cursor.getString(_cursorIndexOfNetId);
          }
          final String _tmpLabel;
          if (_cursor.isNull(_cursorIndexOfLabel)) {
            _tmpLabel = null;
          } else {
            _tmpLabel = _cursor.getString(_cursorIndexOfLabel);
          }
          _item_1 = new PinEntity(_tmpId,_tmpConnectorId,_tmpIndex,_tmpRow,_tmpCol,_tmpNetId,_tmpLabel);
          _tmpRelation.add(_item_1);
        }
      }
    } finally {
      _cursor.close();
    }
  }
}
