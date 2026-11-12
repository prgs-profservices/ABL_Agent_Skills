/*
 * Copyright 2026 Progress Software Corporation
 * SPDX-License-Identifier: Apache-2.0
 */

/*------------------------------------------------------------------------
    File        : compilefile.p
    Purpose     : Compile an OpenEdge ABL source file (.cls, .w, .i, or .p) into a .r file.
    Syntax      : mbpro -p compilefile.p -param<filename>
    Description :
    Author(s)   : S.E. Southwell
    Created     : 01/20/2026
------------------------------------------------------------------------*/


USING Progress.Json.ObjectModel.JsonArray FROM PROPATH.
USING Progress.Json.ObjectModel.JsonObject FROM PROPATH.
USING Progress.Json.ObjectModel.ObjectModelParser FROM PROPATH.

DEFINE VARIABLE cInto AS CHARACTER NO-UNDO.
DEFINE VARIABLE cFilename AS CHARACTER NO-UNDO.
DEFINE VARIABLE lSuccess AS LOGICAL NO-UNDO.

ASSIGN cFilename = SESSION:PARAMETER.

RUN SetPropath.
RUN NormalizeFilename(INPUT-OUTPUT cFilename).
RUN CompileFile(cFilename, OUTPUT lSuccess) NO-ERROR.
IF lSuccess THEN RUN Cleanup(cFilename).

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
    FIX-CODEPAGE(lcJson) = "UTF-8".
    COPY-LOB FROM FILE "openedge-project.json" TO lcJson.

    oParser = NEW ObjectModelParser().
    oRoot = CAST(oParser:Parse(lcJson), JsonObject).

    oBuild = oRoot:GetJsonArray("buildPath").

    DO iIndex = 1 TO oBuild:Length:
        oItem = oBuild:GetJsonObject(iIndex).

        IF cPropath > "" THEN cPropath = cPropath + ",".

        cPropath = cPropath + REPLACE(oItem:GetCharacter("path"), "$~{DLC~}", cDLC).
        IF oItem:GetCharacter("type") = "source" THEN DO:
            cInto = oItem:GetCharacter("build").
        END.
    END.
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
    DEFINE VARIABLE cFilePath AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cDirPath AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iDirEntry AS INTEGER NO-UNDO.
    DEFINE VARIABLE iNumDirs AS INTEGER NO-UNDO.

    ASSIGN cInto = REPLACE("./" + cInto + "/tempess","//","/").
    // message "cInto:" cInto.
    FILE-INFO:FILE-NAME = cInto.
    IF FILE-INFO:FULL-PATHNAME = ? THEN DO:
        OS-CREATE-DIR VALUE(cInto).
    END.

    ASSIGN cFilePath = pcFilename
           iNumDirs = NUM-ENTRIES(cFilePath, "/") - 1.

    DO iDirEntry = 1 TO iNumDirs:
        IF iDirEntry = 1 THEN
            ASSIGN cDirPath = cInto + "/" + ENTRY(iDirEntry, cFilePath, "/").
        ELSE
            ASSIGN cDirPath = cDirPath + "/" + ENTRY(iDirEntry, cFilePath, "/").

        FILE-INFO:FILE-NAME = cDirPath.
        IF FILE-INFO:FULL-PATHNAME = ? THEN DO:
            OS-CREATE-DIR VALUE(cDirPath).
        END.
    END.

    COMPILE VALUE(pcFilename) SAVE INTO VALUE(cInto) NO-ERROR.

    IF ERROR-STATUS:ERROR THEN DO:
        DO iMsg = 1 TO ERROR-STATUS:NUM-MESSAGES:
            IF cMessages > "" THEN
                cMessages = cMessages + CHR(10).
            cMessages = cMessages + ERROR-STATUS:GET-MESSAGE(iMsg).
        END.

        MESSAGE "Compilation failed for:" pcFilename SKIP
                cMessages.
        RETURN.
    END.
    IF COMPILER:ERROR THEN DO:
        DO iMsg = 1 TO COMPILER:NUM-MESSAGES:
            IF cMessages > "" THEN
                cMessages = cMessages + CHR(10).
            cMessages = cMessages + COMPILER:GET-MESSAGE(iMsg).
        END.

        MESSAGE "Compilation failed for:" pcFilename SKIP
                cMessages.
        RETURN.
    END.

    IF COMPILER:WARNING THEN DO:
        DO iMsg = 1 TO COMPILER:NUM-MESSAGES:
            IF cMessages > "" THEN
                cMessages = cMessages + CHR(10).
            cMessages = cMessages + COMPILER:GET-MESSAGE(iMsg).
        END.

        MESSAGE "Compilation completed with warnings for:" pcFilename SKIP
                cMessages.
    END.

    MESSAGE "Compilation successful for:" pcFilename.

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
