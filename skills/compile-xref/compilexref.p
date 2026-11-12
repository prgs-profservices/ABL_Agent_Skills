/*
 * Copyright 2026 Progress Software Corporation
 * SPDX-License-Identifier: Apache-2.0
 */

/*------------------------------------------------------------------------
    File        : compilexref.p
    Purpose     : Compile an OpenEdge ABL source file (.cls, .w, .i, or .p) into a .r file.
    Syntax      : mbpro -p compilexref.p -param <filename>
    Description :
    Author(s)   : S.E. Southwell
    Created     : 1/26/2026
------------------------------------------------------------------------*/


USING Progress.Json.ObjectModel.JsonArray FROM PROPATH.
USING Progress.Json.ObjectModel.JsonObject FROM PROPATH.
USING Progress.Json.ObjectModel.ObjectModelParser FROM PROPATH.

DEFINE VARIABLE cInto AS CHARACTER NO-UNDO.
DEFINE VARIABLE cFilename AS CHARACTER NO-UNDO.
DEFINE VARIABLE lSuccess AS LOGICAL NO-UNDO.

ASSIGN cFilename = SESSION:PARAMETER.
MESSAGE "DEBUG 1".
RUN SetPropath.
MESSAGE "DEBUG 2".

RUN NormalizeFilename(INPUT-OUTPUT cFilename).
MESSAGE "Normalized filename: " + cFilename.
MESSAGE "Propath: " + PROPATH.
RUN CompileFile(cFilename, OUTPUT lSuccess) NO-ERROR.

PROCEDURE SetPropath:
    DEFINE VARIABLE oRoot     AS JsonObject NO-UNDO.
    DEFINE VARIABLE oBuild    AS JsonArray  NO-UNDO.
    DEFINE VARIABLE oItem     AS JsonObject NO-UNDO.
    DEFINE VARIABLE oParser   AS ObjectModelParser NO-UNDO.
    DEFINE VARIABLE lcJson    AS LONGCHAR   NO-UNDO.
    DEFINE VARIABLE cPropath  AS CHARACTER  NO-UNDO.
    DEFINE VARIABLE iIndex    AS INTEGER    NO-UNDO.
    DEFINE VARIABLE cDLC      AS CHARACTER  NO-UNDO.

    cDLC = OS-GETENV("DLC").
    MESSAGE "DLC: " + cDLC.

    FIX-CODEPAGE(lcJson) = "UTF-8".
    COPY-LOB FROM FILE "openedge-project.json" TO lcJson.
MESSAGE "DEBUG 2.1".
    oParser = NEW ObjectModelParser().
    oRoot = CAST(oParser:Parse(lcJson), JsonObject).
MESSAGE "DEBUG 2.2".
    oBuild = oRoot:GetJsonArray("buildPath").
MESSAGE "DEBUG 2.3".
    DO iIndex = 1 TO oBuild:Length:
        oItem = oBuild:GetJsonObject(iIndex).
MESSAGE "DEBUG 2.4".

        IF oItem:GetCharacter("type") = "propath" THEN DO:
MESSAGE "DEBUG 2.5".
            IF cPropath > "" THEN
                cPropath = cPropath + ",".

            cPropath = cPropath + REPLACE(oItem:GetCharacter("path"), "$~{DLC~}", cDLC).
        END.
MESSAGE "DEBUG 2.6".
        IF oItem:Has("type") AND oItem:GetCharacter("type") = "source"
            AND oItem:Has("build") THEN DO:
            cInto = oItem:GetCharacter("build").
        END.
    END.

    MESSAGE "Propath: " + cPropath.
    PROPATH = cPropath.

END PROCEDURE.

PROCEDURE NormalizeFilename:
    DEFINE INPUT-OUTPUT PARAMETER pcFilename AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cTestPath AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iSlashPos AS INTEGER   NO-UNDO.

    ASSIGN pcFilename = REPLACE(pcFilename, "~\", "/").

    ASSIGN cTestPath = pcFilename.

    DO WHILE cTestPath > "":
        FILE-INFO:FILE-NAME = cTestPath.

        IF FILE-INFO:FULL-PATHNAME <> ? THEN DO:
            ASSIGN pcFilename = cTestPath.
            RETURN.
        END.

        ASSIGN iSlashPos = INDEX(cTestPath, "/").

        IF iSlashPos = 0 THEN
            LEAVE.

        ASSIGN cTestPath = SUBSTRING(cTestPath, iSlashPos + 1).
    END.

END PROCEDURE.

PROCEDURE CompileFile:
    DEFINE INPUT PARAMETER pcFilename AS CHARACTER NO-UNDO.
    DEFINE OUTPUT PARAMETER plSuccess AS LOGICAL NO-UNDO.
    DEFINE VARIABLE iMsg      AS INTEGER   NO-UNDO.
    DEFINE VARIABLE cMessages AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iDotPos   AS INTEGER   NO-UNDO.
    DEFINE VARIABLE cFoundFile AS CHARACTER NO-UNDO.

    ASSIGN cFoundFile = SEARCH(pcFilename).

    IF cFoundFile = ? THEN DO:
        MESSAGE "File not found: " pcFilename.
        RETURN.
    END.
    ASSIGN iDotPos = R-INDEX(cFoundFile, ".").

    IF iDotPos > 0 THEN
        ASSIGN cInto = SUBSTRING(cFoundFile, 1, iDotPos - 1) + ".xref".
    ELSE
        ASSIGN cInto = cFoundFile + ".xref".

    COMPILE VALUE(pcFilename) XREF VALUE(cInto).

    IF COMPILER:ERROR THEN DO:
        DO iMsg = 1 TO COMPILER:NUM-MESSAGES:
            IF cMessages > "" THEN
                cMessages = cMessages + CHR(10).
            cMessages = cMessages + COMPILER:GET-MESSAGE(iMsg).
        END.

        MESSAGE "Compilation failed for:" pcFilename SKIP
                cMessages SKIP.
        RETURN.
    END.

    IF ERROR-STATUS:ERROR THEN DO:
        DO iMsg = 1 TO ERROR-STATUS:NUM-MESSAGES:
            IF cMessages > "" THEN
                cMessages = cMessages + CHR(10).
            cMessages = cMessages + ERROR-STATUS:GET-MESSAGE(iMsg).
        END.

        MESSAGE "Compilation failed for:" pcFilename SKIP
                cMessages SKIP.
        RETURN.
    END.

    IF COMPILER:WARNING THEN DO:
        DO iMsg = 1 TO COMPILER:NUM-MESSAGES:
            IF cMessages > "" THEN
                cMessages = cMessages + CHR(10).
            cMessages = cMessages + COMPILER:GET-MESSAGE(iMsg).
        END.

        MESSAGE "Compilation completed with warnings for:" pcFilename SKIP
                cMessages SKIP.
    END.

    MESSAGE "xref compilation successful for:" pcFilename.

    plSuccess = TRUE.
END PROCEDURE.

PROCEDURE Cleanup:
    DEFINE INPUT PARAMETER pcFilename AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cFirstLine AS CHARACTER NO-UNDO.

    IF pcFilename MATCHES "*.w" THEN DO:
        pcFilename = SEARCH(pcFilename).
        IF pcFilename = ? THEN RETURN.
        INPUT FROM VALUE(pcFilename).
        IMPORT UNFORMATTED cFirstLine.
        INPUT CLOSE.

        IF cFirstLine BEGINS "/*E4GL-W*/" THEN DO:
            OS-DELETE VALUE(pcFilename).
        END.
    END.

END PROCEDURE.
