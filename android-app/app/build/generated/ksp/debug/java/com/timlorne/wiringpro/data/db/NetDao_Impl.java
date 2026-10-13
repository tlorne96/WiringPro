package com.timlorne.wiringpro.data.db;

import android.database.Cursor;
import android.os.CancellationSignal;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.room.CoroutinesRoom;
import androidx.room.EntityInsertionAdapter;
import androidx.room.RoomDatabase;
import androidx.room.RoomSQLiteQuery;
import androidx.room.SharedSQLiteStatement;
import androidx.room.util.CursorUtil;
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
public final class NetDao_Impl implements NetDao {
  private final RoomDatabase __db;

  private final EntityInsertionAdapter<NetEntity> __insertionAdapterOfNetEntity;

  private final SharedSQLiteStatement __preparedStmtOfUpdateWireColors;

  public NetDao_Impl(@NonNull final RoomDatabase __db) {
    this.__db = __db;
    this.__insertionAdapterOfNetEntity = new EntityInsertionAdapter<NetEntity>(__db) {
      @Override
      @NonNull
      protected String createQuery() {
        return "INSERT OR REPLACE INTO `nets` (`id`,`projectId`,`name`,`netType`,`color`,`stripeColor`) VALUES (?,?,?,?,?,?)";
      }

      @Override
      protected void bind(@NonNull final SupportSQLiteStatement statement,
          @NonNull final NetEntity entity) {
        statement.bindString(1, entity.getId());
        statement.bindString(2, entity.getProjectId());
        statement.bindString(3, entity.getName());
        statement.bindString(4, entity.getNetType());
        if (entity.getColor() == null) {
          statement.bindNull(5);
        } else {
          statement.bindString(5, entity.getColor());
        }
        if (entity.getStripeColor() == null) {
          statement.bindNull(6);
        } else {
          statement.bindString(6, entity.getStripeColor());
        }
      }
    };
    this.__preparedStmtOfUpdateWireColors = new SharedSQLiteStatement(__db) {
      @Override
      @NonNull
      public String createQuery() {
        final String _query = "UPDATE nets SET color = ?, stripeColor = ? WHERE id = ?";
        return _query;
      }
    };
  }

  @Override
  public Object upsert(final NetEntity net, final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        __db.beginTransaction();
        try {
          __insertionAdapterOfNetEntity.insert(net);
          __db.setTransactionSuccessful();
          return Unit.INSTANCE;
        } finally {
          __db.endTransaction();
        }
      }
    }, $completion);
  }

  @Override
  public Object updateWireColors(final String netId, final String color, final String stripeColor,
      final Continuation<? super Unit> $completion) {
    return CoroutinesRoom.execute(__db, true, new Callable<Unit>() {
      @Override
      @NonNull
      public Unit call() throws Exception {
        final SupportSQLiteStatement _stmt = __preparedStmtOfUpdateWireColors.acquire();
        int _argIndex = 1;
        if (color == null) {
          _stmt.bindNull(_argIndex);
        } else {
          _stmt.bindString(_argIndex, color);
        }
        _argIndex = 2;
        if (stripeColor == null) {
          _stmt.bindNull(_argIndex);
        } else {
          _stmt.bindString(_argIndex, stripeColor);
        }
        _argIndex = 3;
        _stmt.bindString(_argIndex, netId);
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
          __preparedStmtOfUpdateWireColors.release(_stmt);
        }
      }
    }, $completion);
  }

  @Override
  public Flow<List<NetEntity>> observeForProject(final String projectId) {
    final String _sql = "SELECT * FROM nets WHERE projectId = ?";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 1);
    int _argIndex = 1;
    _statement.bindString(_argIndex, projectId);
    return CoroutinesRoom.createFlow(__db, false, new String[] {"nets"}, new Callable<List<NetEntity>>() {
      @Override
      @NonNull
      public List<NetEntity> call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfProjectId = CursorUtil.getColumnIndexOrThrow(_cursor, "projectId");
          final int _cursorIndexOfName = CursorUtil.getColumnIndexOrThrow(_cursor, "name");
          final int _cursorIndexOfNetType = CursorUtil.getColumnIndexOrThrow(_cursor, "netType");
          final int _cursorIndexOfColor = CursorUtil.getColumnIndexOrThrow(_cursor, "color");
          final int _cursorIndexOfStripeColor = CursorUtil.getColumnIndexOrThrow(_cursor, "stripeColor");
          final List<NetEntity> _result = new ArrayList<NetEntity>(_cursor.getCount());
          while (_cursor.moveToNext()) {
            final NetEntity _item;
            final String _tmpId;
            _tmpId = _cursor.getString(_cursorIndexOfId);
            final String _tmpProjectId;
            _tmpProjectId = _cursor.getString(_cursorIndexOfProjectId);
            final String _tmpName;
            _tmpName = _cursor.getString(_cursorIndexOfName);
            final String _tmpNetType;
            _tmpNetType = _cursor.getString(_cursorIndexOfNetType);
            final String _tmpColor;
            if (_cursor.isNull(_cursorIndexOfColor)) {
              _tmpColor = null;
            } else {
              _tmpColor = _cursor.getString(_cursorIndexOfColor);
            }
            final String _tmpStripeColor;
            if (_cursor.isNull(_cursorIndexOfStripeColor)) {
              _tmpStripeColor = null;
            } else {
              _tmpStripeColor = _cursor.getString(_cursorIndexOfStripeColor);
            }
            _item = new NetEntity(_tmpId,_tmpProjectId,_tmpName,_tmpNetType,_tmpColor,_tmpStripeColor);
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
  public Object findByName(final String projectId, final String name,
      final Continuation<? super NetEntity> $completion) {
    final String _sql = "SELECT * FROM nets WHERE projectId = ? AND name = ? LIMIT 1";
    final RoomSQLiteQuery _statement = RoomSQLiteQuery.acquire(_sql, 2);
    int _argIndex = 1;
    _statement.bindString(_argIndex, projectId);
    _argIndex = 2;
    _statement.bindString(_argIndex, name);
    final CancellationSignal _cancellationSignal = DBUtil.createCancellationSignal();
    return CoroutinesRoom.execute(__db, false, _cancellationSignal, new Callable<NetEntity>() {
      @Override
      @Nullable
      public NetEntity call() throws Exception {
        final Cursor _cursor = DBUtil.query(__db, _statement, false, null);
        try {
          final int _cursorIndexOfId = CursorUtil.getColumnIndexOrThrow(_cursor, "id");
          final int _cursorIndexOfProjectId = CursorUtil.getColumnIndexOrThrow(_cursor, "projectId");
          final int _cursorIndexOfName = CursorUtil.getColumnIndexOrThrow(_cursor, "name");
          final int _cursorIndexOfNetType = CursorUtil.getColumnIndexOrThrow(_cursor, "netType");
          final int _cursorIndexOfColor = CursorUtil.getColumnIndexOrThrow(_cursor, "color");
          final int _cursorIndexOfStripeColor = CursorUtil.getColumnIndexOrThrow(_cursor, "stripeColor");
          final NetEntity _result;
          if (_cursor.moveToFirst()) {
            final String _tmpId;
            _tmpId = _cursor.getString(_cursorIndexOfId);
            final String _tmpProjectId;
            _tmpProjectId = _cursor.getString(_cursorIndexOfProjectId);
            final String _tmpName;
            _tmpName = _cursor.getString(_cursorIndexOfName);
            final String _tmpNetType;
            _tmpNetType = _cursor.getString(_cursorIndexOfNetType);
            final String _tmpColor;
            if (_cursor.isNull(_cursorIndexOfColor)) {
              _tmpColor = null;
            } else {
              _tmpColor = _cursor.getString(_cursorIndexOfColor);
            }
            final String _tmpStripeColor;
            if (_cursor.isNull(_cursorIndexOfStripeColor)) {
              _tmpStripeColor = null;
            } else {
              _tmpStripeColor = _cursor.getString(_cursorIndexOfStripeColor);
            }
            _result = new NetEntity(_tmpId,_tmpProjectId,_tmpName,_tmpNetType,_tmpColor,_tmpStripeColor);
          } else {
            _result = null;
          }
          return _result;
        } finally {
          _cursor.close();
          _statement.release();
        }
      }
    }, $completion);
  }

  @NonNull
  public static List<Class<?>> getRequiredConverters() {
    return Collections.emptyList();
  }
}
