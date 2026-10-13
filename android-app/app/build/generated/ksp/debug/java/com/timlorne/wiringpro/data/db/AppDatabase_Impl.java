package com.timlorne.wiringpro.data.db;

import androidx.annotation.NonNull;
import androidx.room.DatabaseConfiguration;
import androidx.room.InvalidationTracker;
import androidx.room.RoomDatabase;
import androidx.room.RoomOpenHelper;
import androidx.room.migration.AutoMigrationSpec;
import androidx.room.migration.Migration;
import androidx.room.util.DBUtil;
import androidx.room.util.TableInfo;
import androidx.sqlite.db.SupportSQLiteDatabase;
import androidx.sqlite.db.SupportSQLiteOpenHelper;
import java.lang.Class;
import java.lang.Override;
import java.lang.String;
import java.lang.SuppressWarnings;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import javax.annotation.processing.Generated;

@Generated("androidx.room.RoomProcessor")
@SuppressWarnings({"unchecked", "deprecation"})
public final class AppDatabase_Impl extends AppDatabase {
  private volatile ProjectDao _projectDao;

  private volatile ConnectorDao _connectorDao;

  private volatile PinDao _pinDao;

  private volatile NetDao _netDao;

  @Override
  @NonNull
  protected SupportSQLiteOpenHelper createOpenHelper(@NonNull final DatabaseConfiguration config) {
    final SupportSQLiteOpenHelper.Callback _openCallback = new RoomOpenHelper(config, new RoomOpenHelper.Delegate(3) {
      @Override
      public void createAllTables(@NonNull final SupportSQLiteDatabase db) {
        db.execSQL("CREATE TABLE IF NOT EXISTS `projects` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, `vehicle` TEXT, `notes` TEXT, `createdAt` INTEGER NOT NULL, `updatedAt` INTEGER NOT NULL, `imagePath` TEXT, PRIMARY KEY(`id`))");
        db.execSQL("CREATE TABLE IF NOT EXISTS `connectors` (`id` TEXT NOT NULL, `projectId` TEXT NOT NULL, `label` TEXT NOT NULL, `rows` TEXT NOT NULL, `partRef` TEXT, PRIMARY KEY(`id`), FOREIGN KEY(`projectId`) REFERENCES `projects`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )");
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_connectors_projectId` ON `connectors` (`projectId`)");
        db.execSQL("CREATE TABLE IF NOT EXISTS `pins` (`id` TEXT NOT NULL, `connectorId` TEXT NOT NULL, `index` INTEGER NOT NULL, `row` INTEGER NOT NULL, `col` INTEGER NOT NULL, `netId` TEXT, `label` TEXT, PRIMARY KEY(`id`), FOREIGN KEY(`connectorId`) REFERENCES `connectors`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE , FOREIGN KEY(`netId`) REFERENCES `nets`(`id`) ON UPDATE NO ACTION ON DELETE SET NULL )");
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_pins_connectorId` ON `pins` (`connectorId`)");
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_pins_netId` ON `pins` (`netId`)");
        db.execSQL("CREATE TABLE IF NOT EXISTS `nets` (`id` TEXT NOT NULL, `projectId` TEXT NOT NULL, `name` TEXT NOT NULL, `netType` TEXT NOT NULL, `color` TEXT, `stripeColor` TEXT, PRIMARY KEY(`id`), FOREIGN KEY(`projectId`) REFERENCES `projects`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )");
        db.execSQL("CREATE INDEX IF NOT EXISTS `index_nets_projectId` ON `nets` (`projectId`)");
        db.execSQL("CREATE TABLE IF NOT EXISTS room_master_table (id INTEGER PRIMARY KEY,identity_hash TEXT)");
        db.execSQL("INSERT OR REPLACE INTO room_master_table (id,identity_hash) VALUES(42, 'd9354899825e6f459a3cfb1e84e5e3bc')");
      }

      @Override
      public void dropAllTables(@NonNull final SupportSQLiteDatabase db) {
        db.execSQL("DROP TABLE IF EXISTS `projects`");
        db.execSQL("DROP TABLE IF EXISTS `connectors`");
        db.execSQL("DROP TABLE IF EXISTS `pins`");
        db.execSQL("DROP TABLE IF EXISTS `nets`");
        final List<? extends RoomDatabase.Callback> _callbacks = mCallbacks;
        if (_callbacks != null) {
          for (RoomDatabase.Callback _callback : _callbacks) {
            _callback.onDestructiveMigration(db);
          }
        }
      }

      @Override
      public void onCreate(@NonNull final SupportSQLiteDatabase db) {
        final List<? extends RoomDatabase.Callback> _callbacks = mCallbacks;
        if (_callbacks != null) {
          for (RoomDatabase.Callback _callback : _callbacks) {
            _callback.onCreate(db);
          }
        }
      }

      @Override
      public void onOpen(@NonNull final SupportSQLiteDatabase db) {
        mDatabase = db;
        db.execSQL("PRAGMA foreign_keys = ON");
        internalInitInvalidationTracker(db);
        final List<? extends RoomDatabase.Callback> _callbacks = mCallbacks;
        if (_callbacks != null) {
          for (RoomDatabase.Callback _callback : _callbacks) {
            _callback.onOpen(db);
          }
        }
      }

      @Override
      public void onPreMigrate(@NonNull final SupportSQLiteDatabase db) {
        DBUtil.dropFtsSyncTriggers(db);
      }

      @Override
      public void onPostMigrate(@NonNull final SupportSQLiteDatabase db) {
      }

      @Override
      @NonNull
      public RoomOpenHelper.ValidationResult onValidateSchema(
          @NonNull final SupportSQLiteDatabase db) {
        final HashMap<String, TableInfo.Column> _columnsProjects = new HashMap<String, TableInfo.Column>(7);
        _columnsProjects.put("id", new TableInfo.Column("id", "TEXT", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsProjects.put("name", new TableInfo.Column("name", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsProjects.put("vehicle", new TableInfo.Column("vehicle", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsProjects.put("notes", new TableInfo.Column("notes", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsProjects.put("createdAt", new TableInfo.Column("createdAt", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsProjects.put("updatedAt", new TableInfo.Column("updatedAt", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsProjects.put("imagePath", new TableInfo.Column("imagePath", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysProjects = new HashSet<TableInfo.ForeignKey>(0);
        final HashSet<TableInfo.Index> _indicesProjects = new HashSet<TableInfo.Index>(0);
        final TableInfo _infoProjects = new TableInfo("projects", _columnsProjects, _foreignKeysProjects, _indicesProjects);
        final TableInfo _existingProjects = TableInfo.read(db, "projects");
        if (!_infoProjects.equals(_existingProjects)) {
          return new RoomOpenHelper.ValidationResult(false, "projects(com.timlorne.wiringpro.data.db.ProjectEntity).\n"
                  + " Expected:\n" + _infoProjects + "\n"
                  + " Found:\n" + _existingProjects);
        }
        final HashMap<String, TableInfo.Column> _columnsConnectors = new HashMap<String, TableInfo.Column>(5);
        _columnsConnectors.put("id", new TableInfo.Column("id", "TEXT", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsConnectors.put("projectId", new TableInfo.Column("projectId", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsConnectors.put("label", new TableInfo.Column("label", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsConnectors.put("rows", new TableInfo.Column("rows", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsConnectors.put("partRef", new TableInfo.Column("partRef", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysConnectors = new HashSet<TableInfo.ForeignKey>(1);
        _foreignKeysConnectors.add(new TableInfo.ForeignKey("projects", "CASCADE", "NO ACTION", Arrays.asList("projectId"), Arrays.asList("id")));
        final HashSet<TableInfo.Index> _indicesConnectors = new HashSet<TableInfo.Index>(1);
        _indicesConnectors.add(new TableInfo.Index("index_connectors_projectId", false, Arrays.asList("projectId"), Arrays.asList("ASC")));
        final TableInfo _infoConnectors = new TableInfo("connectors", _columnsConnectors, _foreignKeysConnectors, _indicesConnectors);
        final TableInfo _existingConnectors = TableInfo.read(db, "connectors");
        if (!_infoConnectors.equals(_existingConnectors)) {
          return new RoomOpenHelper.ValidationResult(false, "connectors(com.timlorne.wiringpro.data.db.ConnectorEntity).\n"
                  + " Expected:\n" + _infoConnectors + "\n"
                  + " Found:\n" + _existingConnectors);
        }
        final HashMap<String, TableInfo.Column> _columnsPins = new HashMap<String, TableInfo.Column>(7);
        _columnsPins.put("id", new TableInfo.Column("id", "TEXT", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsPins.put("connectorId", new TableInfo.Column("connectorId", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsPins.put("index", new TableInfo.Column("index", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsPins.put("row", new TableInfo.Column("row", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsPins.put("col", new TableInfo.Column("col", "INTEGER", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsPins.put("netId", new TableInfo.Column("netId", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsPins.put("label", new TableInfo.Column("label", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysPins = new HashSet<TableInfo.ForeignKey>(2);
        _foreignKeysPins.add(new TableInfo.ForeignKey("connectors", "CASCADE", "NO ACTION", Arrays.asList("connectorId"), Arrays.asList("id")));
        _foreignKeysPins.add(new TableInfo.ForeignKey("nets", "SET NULL", "NO ACTION", Arrays.asList("netId"), Arrays.asList("id")));
        final HashSet<TableInfo.Index> _indicesPins = new HashSet<TableInfo.Index>(2);
        _indicesPins.add(new TableInfo.Index("index_pins_connectorId", false, Arrays.asList("connectorId"), Arrays.asList("ASC")));
        _indicesPins.add(new TableInfo.Index("index_pins_netId", false, Arrays.asList("netId"), Arrays.asList("ASC")));
        final TableInfo _infoPins = new TableInfo("pins", _columnsPins, _foreignKeysPins, _indicesPins);
        final TableInfo _existingPins = TableInfo.read(db, "pins");
        if (!_infoPins.equals(_existingPins)) {
          return new RoomOpenHelper.ValidationResult(false, "pins(com.timlorne.wiringpro.data.db.PinEntity).\n"
                  + " Expected:\n" + _infoPins + "\n"
                  + " Found:\n" + _existingPins);
        }
        final HashMap<String, TableInfo.Column> _columnsNets = new HashMap<String, TableInfo.Column>(6);
        _columnsNets.put("id", new TableInfo.Column("id", "TEXT", true, 1, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsNets.put("projectId", new TableInfo.Column("projectId", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsNets.put("name", new TableInfo.Column("name", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsNets.put("netType", new TableInfo.Column("netType", "TEXT", true, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsNets.put("color", new TableInfo.Column("color", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        _columnsNets.put("stripeColor", new TableInfo.Column("stripeColor", "TEXT", false, 0, null, TableInfo.CREATED_FROM_ENTITY));
        final HashSet<TableInfo.ForeignKey> _foreignKeysNets = new HashSet<TableInfo.ForeignKey>(1);
        _foreignKeysNets.add(new TableInfo.ForeignKey("projects", "CASCADE", "NO ACTION", Arrays.asList("projectId"), Arrays.asList("id")));
        final HashSet<TableInfo.Index> _indicesNets = new HashSet<TableInfo.Index>(1);
        _indicesNets.add(new TableInfo.Index("index_nets_projectId", false, Arrays.asList("projectId"), Arrays.asList("ASC")));
        final TableInfo _infoNets = new TableInfo("nets", _columnsNets, _foreignKeysNets, _indicesNets);
        final TableInfo _existingNets = TableInfo.read(db, "nets");
        if (!_infoNets.equals(_existingNets)) {
          return new RoomOpenHelper.ValidationResult(false, "nets(com.timlorne.wiringpro.data.db.NetEntity).\n"
                  + " Expected:\n" + _infoNets + "\n"
                  + " Found:\n" + _existingNets);
        }
        return new RoomOpenHelper.ValidationResult(true, null);
      }
    }, "d9354899825e6f459a3cfb1e84e5e3bc", "385c6a2f1ccdd67d1469c1e22d4357d4");
    final SupportSQLiteOpenHelper.Configuration _sqliteConfig = SupportSQLiteOpenHelper.Configuration.builder(config.context).name(config.name).callback(_openCallback).build();
    final SupportSQLiteOpenHelper _helper = config.sqliteOpenHelperFactory.create(_sqliteConfig);
    return _helper;
  }

  @Override
  @NonNull
  protected InvalidationTracker createInvalidationTracker() {
    final HashMap<String, String> _shadowTablesMap = new HashMap<String, String>(0);
    final HashMap<String, Set<String>> _viewTables = new HashMap<String, Set<String>>(0);
    return new InvalidationTracker(this, _shadowTablesMap, _viewTables, "projects","connectors","pins","nets");
  }

  @Override
  public void clearAllTables() {
    super.assertNotMainThread();
    final SupportSQLiteDatabase _db = super.getOpenHelper().getWritableDatabase();
    final boolean _supportsDeferForeignKeys = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP;
    try {
      if (!_supportsDeferForeignKeys) {
        _db.execSQL("PRAGMA foreign_keys = FALSE");
      }
      super.beginTransaction();
      if (_supportsDeferForeignKeys) {
        _db.execSQL("PRAGMA defer_foreign_keys = TRUE");
      }
      _db.execSQL("DELETE FROM `projects`");
      _db.execSQL("DELETE FROM `connectors`");
      _db.execSQL("DELETE FROM `pins`");
      _db.execSQL("DELETE FROM `nets`");
      super.setTransactionSuccessful();
    } finally {
      super.endTransaction();
      if (!_supportsDeferForeignKeys) {
        _db.execSQL("PRAGMA foreign_keys = TRUE");
      }
      _db.query("PRAGMA wal_checkpoint(FULL)").close();
      if (!_db.inTransaction()) {
        _db.execSQL("VACUUM");
      }
    }
  }

  @Override
  @NonNull
  protected Map<Class<?>, List<Class<?>>> getRequiredTypeConverters() {
    final HashMap<Class<?>, List<Class<?>>> _typeConvertersMap = new HashMap<Class<?>, List<Class<?>>>();
    _typeConvertersMap.put(ProjectDao.class, ProjectDao_Impl.getRequiredConverters());
    _typeConvertersMap.put(ConnectorDao.class, ConnectorDao_Impl.getRequiredConverters());
    _typeConvertersMap.put(PinDao.class, PinDao_Impl.getRequiredConverters());
    _typeConvertersMap.put(NetDao.class, NetDao_Impl.getRequiredConverters());
    return _typeConvertersMap;
  }

  @Override
  @NonNull
  public Set<Class<? extends AutoMigrationSpec>> getRequiredAutoMigrationSpecs() {
    final HashSet<Class<? extends AutoMigrationSpec>> _autoMigrationSpecsSet = new HashSet<Class<? extends AutoMigrationSpec>>();
    return _autoMigrationSpecsSet;
  }

  @Override
  @NonNull
  public List<Migration> getAutoMigrations(
      @NonNull final Map<Class<? extends AutoMigrationSpec>, AutoMigrationSpec> autoMigrationSpecs) {
    final List<Migration> _autoMigrations = new ArrayList<Migration>();
    return _autoMigrations;
  }

  @Override
  public ProjectDao projectDao() {
    if (_projectDao != null) {
      return _projectDao;
    } else {
      synchronized(this) {
        if(_projectDao == null) {
          _projectDao = new ProjectDao_Impl(this);
        }
        return _projectDao;
      }
    }
  }

  @Override
  public ConnectorDao connectorDao() {
    if (_connectorDao != null) {
      return _connectorDao;
    } else {
      synchronized(this) {
        if(_connectorDao == null) {
          _connectorDao = new ConnectorDao_Impl(this);
        }
        return _connectorDao;
      }
    }
  }

  @Override
  public PinDao pinDao() {
    if (_pinDao != null) {
      return _pinDao;
    } else {
      synchronized(this) {
        if(_pinDao == null) {
          _pinDao = new PinDao_Impl(this);
        }
        return _pinDao;
      }
    }
  }

  @Override
  public NetDao netDao() {
    if (_netDao != null) {
      return _netDao;
    } else {
      synchronized(this) {
        if(_netDao == null) {
          _netDao = new NetDao_Impl(this);
        }
        return _netDao;
      }
    }
  }
}
