@Grab('org.codehaus.groovy:groovy-all:2.2.2')
@Grab(group='org.xerial', module='sqlite-jdbc', version='3.36.0.3')

import java.nio.file.Path
import groovy.sql.Sql
import org.slf4j.Logger

import MgiFlagfile
import Eventfile

class MetadataDB {
    Sql db
    Logger log

    MetadataDB(path, log=null) {
        this.db = Sql.newInstance("jdbc:sqlite:$path", "org.sqlite.JDBC")
        this.log = log
    }

    def setup() {
        log.debug("Setting up database")
        db.execute("""
            CREATE TABLE IF NOT EXISTS successfiles (
                flowcell TEXT NOT NULL UNIQUE,
                path TEXT NOT NULL,
                lastmodified INTEGER NOT NULL
            )
            """.stripIndent()
        )

        db.execute("""
            CREATE TABLE IF NOT EXISTS flagfiles (
                flowcell TEXT NOT NULL UNIQUE,
                path TEXT NOT NULL,
                lastmodified INTEGER NOT NULL
            )
            """.stripIndent()
        )

        db.execute("""
            CREATE TABLE IF NOT EXISTS rtacompletefiles (
                flowcell TEXT NOT NULL UNIQUE,
                seqtype TEXT NOT NULL,
                path TEXT NOT NULL,
                lastmodified INTEGER NOT NULL
            )
            """.stripIndent()
        )

        db.execute("""
            CREATE TABLE IF NOT EXISTS eventfiles (
                filename TEXT NOT NULL,
                data TEXT NOT NULL UNIQUE,
                lastmodified INTEGER NOT NULL,
                flowcell TEXT NOT NULL,
                lastlaunched INTEGER
            )
            """.stripIndent()
        )

        db.execute("""
            CREATE TABLE IF NOT EXISTS runinfofiles (
                filename TEXT NOT NULL,
                data TEXT NOT NULL UNIQUE,
                lastmodified INTEGER NOT NULL,
                flowcell TEXT NOT NULL,
                lastlaunched INTEGER
            )
            """.stripIndent()
        )
    }

    def insert(MgiSuccessfile success) {
        log.debug("Database | Inserting new MGI Success file (${success.flowcell}, found here ${success.path}) into database")
        db.execute(
            """
            INSERT INTO successfiles (flowcell, path, lastmodified)
            VALUES(?,?,?)
            ON CONFLICT (flowcell) DO
            UPDATE SET
                lastmodified=excluded.lastmodified,
                path=excluded.path
            """.stripIndent(),
            [success.flowcell, success.path, success.lastmodified]
        )
        return success
    }

    def insert(MgiFlagfile flag) {
        log.debug("Database | Inserting new MGI T7 Flag file (${flag.flowcell}, found here ${flag.path}) into database")
        db.execute(
            """
            INSERT INTO flagfiles (flowcell, path, lastmodified)
            VALUES(?,?,?)
            ON CONFLICT (flowcell) DO
            UPDATE SET
                lastmodified=excluded.lastmodified,
                path=excluded.path
            """.stripIndent(),
            [flag.flowcell, flag.path, flag.lastmodified]
        )
        return flag
    }

    def insert(IlluminaRTACompletefile rta) {
        log.debug("Database | Inserting new Illumina RTAcomplete file (${rta.flowcell}, for ${rta.seqtype} run, found here ${rta.path}) into database")
        db.execute(
            """
            INSERT INTO rtacompletefiles (flowcell, seqtype, path, lastmodified)
            VALUES(?,?,?,?)
            ON CONFLICT (flowcell) DO
            UPDATE SET
                seqtype=excluded.seqtype,
                lastmodified=excluded.lastmodified,
                path=excluded.path
            """.stripIndent(),
            [rta.flowcell, rta.seqtype, rta.path, rta.lastmodified]
        )
        return rta
    }

    def insert(Eventfile evt) {
        log.debug("Database | Inserting new Clarity Event file (${evt.flowcell}) into database")
        db.execute(
            """
            INSERT INTO eventfiles (filename, flowcell, lastmodified, data)
            VALUES (?,?,?,?)
            ON CONFLICT (data) DO
            UPDATE SET
                lastmodified=excluded.lastmodified,
                filename=excluded.filename
            """.stripIndent(),
            [evt.filename, evt.flowcell, evt.lastmodified, evt.text]
        )
        return evt
    }

    def insert(RunInfofile runinfo) {
        log.debug("Database | Inserting new Freezeman Run Info file (${runinfo.flowcell}) into database")
        db.execute(
            """
            INSERT INTO runinfofiles (filename, flowcell, lastmodified, data)
            VALUES (?,?,?,?)
            ON CONFLICT (data) DO
            UPDATE SET
                lastmodified=excluded.lastmodified,
                filename=excluded.filename
            """.stripIndent(),
            [runinfo.filename, runinfo.flowcell, runinfo.lastmodified, runinfo.text]
        )
        return runinfo
    }

    Eventfile latestEventfile(String flowcell) {
        log.debug("Database | Looking for Clarity Event file for flowcell '$flowcell'")
        def rows = db.rows('''
        WITH ranked_messages AS (
            SELECT
                filename,
                flowcell,
                data,
                lastmodified,
                lastlaunched,
                ROW_NUMBER() OVER (PARTITION BY flowcell ORDER BY lastmodified DESC) AS rn
            FROM eventfiles AS e
            WHERE flowcell = :flowcell
        )
        SELECT * FROM ranked_messages
        WHERE rn = 1
        ORDER BY lastmodified DESC;
        ''', [flowcell:flowcell]
        )
        if(rows.size() == 0) {
            log.debug("Database | No Event file found for flowcell '$flowcell'...")
            return null
        } else {
            def row = rows[0]
            log.debug("Database | Event file found  for flowcell '$flowcell' !")
            return new Eventfile(row.data, row.filename, row.lastlaunched, log)
        }
    }

    RunInfofile latestRunInfofile(String flowcell) {
        log.debug("Database | Looking for Freezeman Run Info file for flowcell '$flowcell'")
        def rows = db.rows('''
        WITH ranked_messages AS (
            SELECT
                filename,
                flowcell,
                data,
                lastmodified,
                lastlaunched,
                ROW_NUMBER() OVER (PARTITION BY flowcell ORDER BY lastmodified DESC) AS rn
            FROM runinfofiles AS r
            WHERE flowcell = :flowcell
        )
        SELECT * FROM ranked_messages
        WHERE rn = 1
        ORDER BY lastmodified DESC;
        ''', [flowcell:flowcell]
        )
        if(rows.size() == 0) {
            log.debug("Database | No Run Info file found for flowcell '$flowcell'...")
            return null
        } else {
            def row = rows[0]
            log.debug("Database | Run Info file found for flowcell '$flowcell' !")
            return new RunInfofile(row.data, row.filename, row.lastlaunched, log)
        }
    }

    Boolean hasSuccessfile(Eventfile event) {
        def flowcell = event.flowcell
        def rows = db.rows('SELECT * FROM successfiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    Boolean hasSuccessfile(RunInfofile runinfo) {
        def flowcell = runinfo.flowcell
        def rows = db.rows('SELECT * FROM successfiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    Boolean hasFlagfile(Eventfile event) {
        def flowcell = event.flowcell
        def rows = db.rows('SELECT * FROM flagfiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    Boolean hasFlagfile(RunInfofile runinfo) {
        def flowcell = runinfo.flowcell
        def rows = db.rows('SELECT * FROM flagfiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    Boolean hasRTAcompletefile(Eventfile event) {
        def flowcell = event.flowcell
        def rows = db.rows('SELECT * FROM rtacompletefiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    Boolean hasRTAcompletefile(RunInfofile runinfo) {
        def flowcell = runinfo.flowcell
        def rows = db.rows('SELECT * FROM rtacompletefiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    String seqType(Eventfile event) {
        def flowcell = event.flowcell
        def rows = db.rows('SELECT * FROM rtacompletefiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        if (rows.size() == 0) {
            log.debug("Database | no rtacompletefiles found for flowcell '${flowcell}' !")
            return null
        } else {
            def row = rows[0]
            log.debug("Database | found rtacompletefiles for flowcell '${flowcell} !")
            return row.seqtype
        }
    }

    String seqType(RunInfofile runinfo) {
        def flowcell = runinfo.flowcell
        def rows = db.rows('SELECT * FROM rtacompletefiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        if (rows.size() == 0) {
            log.debug("Database | no rtacompletefiles found for flowcell '${flowcell} !")
            return null
        } else {
            def row = rows[0]
            log.debug("Database | found rtacompletefiles for flowcell '${flowcell} !")
            return row.seqtype
        }
    }

    def markAsLaunched(Eventfile event) {
        log.debug("Database | Marking Clarity Event file as launched '${event.flowcell}'")
        def text = event.text
        def rows = db.rows('SELECT * FROM eventfiles WHERE data = :data', [data: text])
        if(rows.size() == 0) {
            log.warn("Could not find rows to update lastlaunched date")
        } else {
            db.execute("UPDATE eventfiles SET lastlaunched=strftime('%s','now') WHERE data=:data", [data: text])
        }
    }

    def markAsLaunched(RunInfofile runinfo) {
        log.debug("Database | Marking Freezeman Run Info file as launched '${runinfo.flowcell}'")
        def text = runinfo.text
        def rows = db.rows('SELECT * FROM runinfofiles WHERE data = :data', [data: text])
        if(rows.size() == 0) {
            log.warn("Could not find rows to update lastlaunched date")
        } else {
            db.execute("UPDATE runinfofiles SET lastlaunched=strftime('%s','now') WHERE data=:data", [data: text])
        }
    }
}