/*
 * libpq-cmake smoke test:
 *   1. PQconnectdb against $PG_CONNINFO (or argv[1])
 *   2. SELECT 42, verify the cell value
 *   3. Print libpq version + SSL state, exit 0 on success
 *
 * Exit codes:
 *   0 - success
 *   1 - connection failed
 *   2 - SELECT result mismatch
 */
#include <libpq-fe.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *conninfo = NULL;
    if (argc > 1 && argv[1][0] != '\0') {
        conninfo = argv[1];
    } else {
        conninfo = getenv("PG_CONNINFO");
    }
    if (conninfo == NULL || conninfo[0] == '\0') {
        conninfo = "host=localhost port=5432 user=postgres "
                   "password=postgres dbname=postgres";
    }

    PGconn *conn = PQconnectdb(conninfo);
    if (PQstatus(conn) != CONNECTION_OK) {
        fprintf(stderr, "connect failed: %s", PQerrorMessage(conn));
        PQfinish(conn);
        return 1;
    }

    PGresult *res = PQexec(conn, "SELECT 42");
    if (PQresultStatus(res) != PGRES_TUPLES_OK) {
        fprintf(stderr, "SELECT failed: %s", PQerrorMessage(conn));
        PQclear(res);
        PQfinish(conn);
        return 2;
    }
    const char *cell = PQgetvalue(res, 0, 0);
    if (cell == NULL || strcmp(cell, "42") != 0) {
        fprintf(stderr, "SELECT 42 returned '%s'\n", cell ? cell : "(null)");
        PQclear(res);
        PQfinish(conn);
        return 2;
    }

    printf("libpq %d, server '%s', SSL=%s\n",
           PQlibVersion(),
           PQparameterStatus(conn, "server_version"),
           PQsslInUse(conn) ? "yes" : "no");

    PQclear(res);
    PQfinish(conn);
    return 0;
}
