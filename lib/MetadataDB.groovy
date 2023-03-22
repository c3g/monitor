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
            CREATE TABLE IF NOT EXISTS flagfiles (
                flowcell TEXT NOT NULL UNIQUE,
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

    Boolean hasFlagfile(Eventfile evt) {
        def flowcell = evt.flowcell
        def rows = db.rows('SELECT * FROM flagfiles WHERE flowcell = :flowcell', [flowcell:flowcell])
        rows.size() >= 0
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

    def lastestEventfileForFlowcell(String flowcell) {
        log.debug("Database | Looking for event file for flowcell '$flowcell'")
        def rows = db.rows('''
        WITH ranked_messages AS (
            SELECT
                filename,
                flowcell,
                data,
                lastmodified,
                ROW_NUMBER() OVER (PARTITION BY flowcell ORDER BY lastmodified DESC) AS rn
            FROM eventfiles AS e
            WHERE flowcell = :flowcell
        )
        SELECT * FROM ranked_messages
        WHERE rn = 1
        ORDER BY lastmodified DESC;
        ''', [flowcell:flowcell]
        )
        rows.size() == 0 ? null : rows[0]
    }
}