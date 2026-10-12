package com.timlorne.wiringpro.data.db;

import android.database.Cursor;
import androidx.annotation.NonNull;
import androidx.room.CoroutinesRoom;
import androidx.room.EntityInsertionAdapter;
import androidx.room.RoomDatabase;
import androidx.room.RoomSQLiteQuery;
import androidx.room.SharedSQLiteStatement;
import androidx.room.util.DBUtil;
import androidx.sqlite.db.SupportSQLiteStatement;
import java.lang.Class;
import java.lang.Exception;
import java.lang.Object;
import java.lang.Override;
import java.lang.String;
import java.lang.SuppressWarnings;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.Callable;
import javax.annotation.processing.Generated;
import kotlin.Unit;
import kotlin.coroutines.Continuation;
import kotlinx.coroutines.flow.Flow;

@Generated("androidx.room.RoomProcessor")
@SuppressWarnings({"unchecked", "deprecation"})
public final class PinDao_Impl implements PinDao {
  private final RoomDatabase __db;

  private final EntityInsertionAdapter<PinEntity> __insertionAdapterOfPinEntity;

  private final SharedSQLiteStatement __preparedStmtOfAssignNet;

  private final SharedSQLiteStatement __preparedStmtOfSetLabel;

  public PinDao_Impl(@NonNull final RoomDatabase __db) {
    this.__db = __db;
    this.__insertionAdapterOfPinEntity = new EntityInsertionAdapter<PinEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT OR REPLACE INTO `pins` (`id`,`connectorId`,`index`,`row`,`col`,`netId`,`label`) VALUES (?,?,?,?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final PinEntity entity) {
        statement.bindString(1, entity.getId());
        statement.bindString(2, entity.getConnectorId());
        statement.bindLong(3, entity.getIndex());
        statement.bindLong(4, entity.getRow());
        statement.bindLong(5, entity.getCol());
        if (entity.getNetId() == null) {
          statement.bindNull(6);
        } else {
          statement.bindString(6, entity.getNetId());
        }
        if (entity.getLabel() == null) {
          statement.bindNull(7);
        } else {
          statement.bindString(7, entity.getLabel());
        }
      }
    };
    this.__preparedStmtOfAssignNet = new SharedSQLiteStatement(__db) {
      @Override
      @NonNull
      public String createQuery() {
        final String _query = "UPDATE pins SET netId = ? WHERE id = ?";
        return _query;
      }
    };
    this.__preparedStmtOfSetLabel = new SharedSQLiteStatement(__db) {
      @Override
      @NonNull
      public String createQuery() {
        final String _query = "UPDATE pins SET label = ? WHERE id = ?";
        return _query;
      }
    };
  }

  @Override
  public Object upsertAll(final List<PinEntity> pins,
      final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        __db.beginTransaction();
        try {
          __insertionAdapterOfPinEntity.insert(pins);
          __db.setTransactionSuccessful();
          return Unit.INSTANCE;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Object assignNet(final String pinId, final String netId,
      final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        final SupportSQLiteStatement _stmt = __preparedStmtOfAssignNet.acquire();
        int _argIndex = 1;
        if (netId == null) {
          _stmt.bindNull(_argIndex);
        } else {
          _stmt.bindString(_argIndex, netId);
        }
        _argIndex = 2;
        _stmt.bindString(_argIndex, pinId);
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
          __preparedStmtOfAssignNet.release(_stmt);
        }
      }
    }, $completion);
  }

  @Override
  public Object setLabel(final String pinId, final String label,
      final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        final SupportSQLiteStatement _stmt = __preparedStmtOfSetLabel.acquire();
        int _argIndex = 1;
        if (label == null) {
          _stmt.bindNull(_argIndex);
        } else {
          _stmt.bindString(_argIndex, label);
        }
        _argIndex = 2;
        _stmt.bindString(_argIndex, pinId);
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
          __preparedStmtOfSetLabel.release(_stmt);
        }
      }
    }, $completion);
  }

  @Override
  public Flow<List<PinAssignmentRow>> observeAssignmentsForProject(final String projectId) {
    final String _sql = "\n"
            + "        SELECT c.label AS connectorLabel, p.`index` AS pinIndex, p.netId AS netId\n"
            + "        FROM pins p\n"
            + "        INNER JOIN connectors c ON p.connectorId = c.id\n"
            + "        WHERE c.projectId = ? AND p.netId IS NOT NULL\n"
            + "        ";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindString(_argIndex, projectId);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"pins",
        "connectors"}, new Callable<List<PinAssignmentRow>>() {
      @Override
      @NonNull
      public List<PinAssignmentRow> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfConnectorLabel = 0;
          final int _cursorIndexOfPinIndex = 1;
          final int _cursorIndexOfNetId = 2;
          final List<PinAssignmentRow> _result = new ArrayList<PinAssignmentRow>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final PinAssignmentRow _item;
            final String _tmpConnectorLabel;
            _tmpConnectorLabel = _cursor.getString(_cursorIndexOfConnectorLabel);
            final int _tmpPinIndex;
            _tmpPinIndex = _cursor.getInt(_cursorIndexOfPinIndex);
            final String _tmpNetId;
            _tmpNetId = _cursor.getString(_cursorIndexOfNetId);
            _item = new PinAssignmentRow(_tmpConnectorLabel,_tmpPinIndex,_tmpNetId);
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

  @NonNull
  public static List<Class<?>> getRequiredConverters() {
    return Collections.emptyList();
  }
}
