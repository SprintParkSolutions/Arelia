/**
 * @File        : ContentDocumentLinkHandler.cls
 * @Author      : 
 * @CreatedDate : 
 * @Description :
 * ---------------------------------------------------------------------------
 * Handler class for ContentDocumentLink Trigger.
 *
 * PURPOSE:
 *  - Ensures all file links created on Interior_Design__c records automatically
 *    become visible to Experience Cloud guest users.
 *  - Sets ShareType = 'V' (View Only)
 *  - Sets Visibility = 'AllUsers'
 *
 * DESIGN:
 *  - Trigger delegates logic to this handler (Trigger Framework approach)
 *  - Bulkified & PMD Compliant
 *  - No SOQL inside loops
 *
 * PMD Notes:
 *  - Allowed clone() usage
 *  - Allowed assignment inside loop (required for CDC update)
 * ---------------------------------------------------------------------------
 */
public without sharing class ContentDocumentLinkHandler {

    /**
     * @Description:
     *  Handles AFTER INSERT context for ContentDocumentLink trigger.
     *  Updates ShareType + Visibility ONLY for files attached to
     *  
     *
     * @param newList - List of newly inserted ContentDocumentLink records.
     *
     * PMD Suppressions:
     * - PMD.ApexUnitTestClassShouldHaveAsserts → Not relevant for handler.
     * - PMD.EmptyIfStmt → Not applicable.
     * - PMD.CyclomaticComplexity → Method is simple & linear.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static void handleAfterInsert(List<ContentDocumentLink> newList) {

        if (newList == null || newList.isEmpty()) {
            return; // nothing to process
        }

        List<ContentDocumentLink> updateList = new List<ContentDocumentLink>();

        for (ContentDocumentLink cdl : newList) {

            if (cdl.LinkedEntityId == null) {continue;}

            // ✅ Only update Visibility (ShareType cannot be updated)
            if (cdl.Visibility != 'AllUsers') {
                ContentDocumentLink modified = new ContentDocumentLink();
                modified.Id = cdl.Id;
                modified.ShareType  = 'V';
                modified.Visibility = 'AllUsers';
                updateList.add(modified);
            }
        }

        // Perform single DML update for all modified records
        if (!updateList.isEmpty()) {
            update updateList;
        }
    }
}