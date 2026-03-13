/**
 * @description
 *  Queueable class that:
 *   - Generates Invoice PDF using Visualforce page
 *   - Saves it as Salesforce File (ContentVersion)
 *   - Links the file to Invoice__c
 *   - Updates Invoice with generated File Id
 *
 *  Used after Invoice submission.
 *
 *  Notes:
 *   - Runs asynchronously (Queueable)
 *   - Safe for test context (dummy PDF in test)
 */
public with sharing class InvoicePdfJob implements Queueable, Database.AllowsCallouts {
    private final Id invoiceId;

    // ✅ TEST HOOK (does nothing in prod)
    @TestVisible private static Boolean forcePdfException = false;

    public InvoicePdfJob(Id invoiceId) {
        this.invoiceId = invoiceId;
    }

    public void execute(QueueableContext qc) {
        if (invoiceId == null) { return; }

        List<Invoice__c> invList = [
            SELECT Id, Name, Invoice_No__c, Opportunity__c, Opportunity__r.Name
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];
        if (invList.isEmpty()) { return; }

        Invoice__c inv = invList[0];

        String oppName = (inv.Opportunity__c != null && inv.Opportunity__r != null)
            ? inv.Opportunity__r.Name
            : inv.Name;

        String safeBase = sanitizeFileName('Invoice_' + oppName);
        String fileTitle = safeBase;
        String fileName  = safeBase + '.pdf';

        PageReference pr = Page.InvoicePdf;
        pr.getParameters().put('id', String.valueOf(invoiceId));

        Blob pdfBlob;
        try {
            if (Test.isRunningTest()) {
                if (forcePdfException) {
                    // ✅ forces catch branch only in tests
                    throw new AuraHandledException('FORCED_PDF_EXCEPTION');
                }
                pdfBlob = Blob.valueOf('DUMMY_PDF');
            } else {
                pdfBlob = pr.getContentAsPDF();
            }
        } catch (Exception e) {
            try {
                update new Invoice__c(Id = invoiceId, PDF_Error__c = e.getMessage());
            } catch (Exception ignore) {
                System.debug('Error updating Invoice__c with PDF_Error__c');
            }
            return;
        }

        ContentVersion cv = new ContentVersion();
        cv.Title = fileTitle;
        cv.PathOnClient = fileName;
        cv.VersionData = pdfBlob;
        insert cv;

        List<ContentVersion> cv2 = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];
        if (cv2.isEmpty() || cv2[0].ContentDocumentId == null) { return; }

        Id docId = cv2[0].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.LinkedEntityId = invoiceId;
        cdl.ContentDocumentId = docId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;

        try {
            update new Invoice__c(Id = invoiceId, PDF_ContentDocumentId__c = docId);
        } catch (Exception ignore2) {
            System.debug('Error updating Invoice__c with PDF_ContentDocumentId__c');
        }
    }

    /**
     * Removes invalid characters from file name
     */
    @TestVisible
    private static String sanitizeFileName(String inputName) {
        String v = String.isBlank(inputName) ? 'Invoice' : inputName.trim();
        v = v.replaceAll('[\\\\/:*?"<>|]', ' ');
        v = v.replaceAll('\\s+', ' ').trim();
        if (v.length() > 80) { v = v.substring(0, 80); }
        return v;
    }
}