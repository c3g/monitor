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

    def insert(MgiSuccessfile sf) {
        log.debug("Database | Inserting new success (${sf.flowcell}) into database")
        db.execute(
            """
            INSERT INTO successfiles (flowcell, path, lastmodified)
            VALUES(?,?,?)
            ON CONFLICT (flowcell) DO
            UPDATE SET
                lastmodified=excluded.lastmodified,
                path=excluded.path
            """.stripIndent(),
            [sf.flowcell, sf.path, sf.lastmodified]
        )
        return sf
    }

    def insert(MgiFlagfile ff) {
        log.debug("Database | Inserting new flagfile (${ff.flowcell}) into database")
        db.execute(
            """
            INSERT INTO flagfiles (flowcell, path, lastmodified)
            VALUES(?,?,?)
            ON CONFLICT (flowcell) DO
            UPDATE SET
                lastmodified=excluded.lastmodified,
                path=excluded.path
            """.stripIndent(),
            [ff.flowcell, ff.path, ff.lastmodified]
        )
        return ff
    }

    def insert(IlluminaRTACompletefile rf) {
        log.debug("Database | Inserting new RTAcomplete (${rf.flowcell}, for ${rf.seqtype} run, found here ${rf.path}) into database")
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
            [rf.flowcell, rf.seqtype, rf.path, rf.lastmodified]
        )
        return rf
    }

    def insert(Eventfile evt) {
        log.debug("Database | Inserting new eventfile (${evt.flowcell}) into database")
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

    def insert(RunInfofile runinf) {
        log.debug("Database | Inserting new runinfofiles (${runinf.flowcell}) into database")
        db.execute(
            """
            INSERT INTO runinfofiles (filename, flowcell, lastmodified, data)
            VALUES (?,?,?,?)
            ON CONFLICT (data) DO
            UPDATE SET
                lastmodified=excluded.lastmodified,
                filename=excluded.filename
            """.stripIndent(),
            [runinf.filename, runinf.flowcell, runinf.lastmodified, runinf.text]
        )
        return runinf
    }

    Eventfile latestEventfile(String flowcell) {
        log.debug("Database | Looking for event file for flowcell '$flowcell'")
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
            log.debug("Database | not found !")
            return null
        } else {
            def row = rows[0]
            log.debug("Database | found !")
            return new Eventfile(row.data, row.filename, row.lastlaunched, log)
        }
    }

    RunInfofile latestRunInfofile(String flowcell) {
        log.debug("Database | Looking for runinfo file for flowcell '$flowcell'")
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
            log.debug("Database | not found !")
            return null
        } else {
            def row = rows[0]
            log.debug("Database | found !")
            return new RunInfofile(row.data, row.filename, row.lastlaunched, log)
        }
    }

    Boolean hasSuccessfile(Eventfile evt) {
        def flowcell = evt.flowcell
        def rows = db.rows('SELECT * FROM successfiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    Boolean hasSuccessfile(RunInfofile runinf) {
        def flowcell = runinf.flowcell
        def rows = db.rows('SELECT * FROM successfiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    Boolean hasFlagfile(Eventfile evt) {
        def flowcell = evt.flowcell
        def rows = db.rows('SELECT * FROM flagfiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    Boolean hasFlagfile(RunInfofile runinf) {
        def flowcell = runinf.flowcell
        def rows = db.rows('SELECT * FROM flagfiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    Boolean hasRTAcompletefile(Eventfile evt) {
        def flowcell = evt.flowcell
        def rows = db.rows('SELECT * FROM rtacompletefiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    Boolean hasRTAcompletefile(RunInfofile runinf) {
        def flowcell = runinf.flowcell
        def rows = db.rows('SELECT * FROM rtacompletefiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
    }

    String seqType(Eventfile evt) {
        def flowcell = evt.flowcell
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

    String seqType(RunInfofile runinf) {
        def flowcell = runinf.flowcell
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

    def markAsLaunched(Eventfile evt) {
        log.debug("Database | Marking eventfile as launched '${evt.flowcell}'")
        def text = evt.text
        def rows = db.rows('SELECT * FROM eventfiles WHERE data = :data', [data: text])
        if(rows.size() == 0) {
            log.warn("Could not find rows to update lastlaunched date")
        } else {
            db.execute("UPDATE eventfiles SET lastlaunched=strftime('%s','now') WHERE data=:data", [data: text])
        }
    }

    def markAsLaunched(RunInfofile runinf) {
        log.debug("Database | Marking runinfofile as launched '${runinf.flowcell}'")
        def text = runinf.text
        def rows = db.rows('SELECT * FROM runinfofiles WHERE data = :data', [data: text])
        if(rows.size() == 0) {
            log.warn("Could not find rows to update lastlaunched date")
        } else {
            db.execute("UPDATE runinfofiles SET lastlaunched=strftime('%s','now') WHERE data=:data", [data: text])
        }
    }
}