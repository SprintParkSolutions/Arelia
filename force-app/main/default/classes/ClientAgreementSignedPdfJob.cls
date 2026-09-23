/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementSignedPdfJob
 * Author          : <YourName>
 * Created Date    : Jun 11, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 11, 2026
 * Description     : Saves signed agreement PDF and emails supervisor with signed PDF
 *                   plus selected supporting files linked to Client_Agreement__c.
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 11, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

/**
 * @description Saves the signed Client Agreement PDF and sends:
 *              1. Existing supervisor notification with signed PDF
 *                 and supporting attachments.
 *              2. Client confirmation email with signed PDF.
 *
 * Existing functionality and UI remain unchanged.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ClientAgreementSignedPdfJob implements Queueable {

    private Id agreementId;
    private String signedPdfBase64;

    public ClientAgreementSignedPdfJob(Id agreementId) {
        this.agreementId = agreementId;
    }

    public ClientAgreementSignedPdfJob(
        Id agreementId,
        String signedPdfBase64
    ) {
        this.agreementId = agreementId;
        this.signedPdfBase64 = signedPdfBase64;
    }

    public void execute(QueueableContext context) {

        if (agreementId == null) {
            System.debug(
                'ClientAgreementSignedPdfJob failed: agreementId is null.'
            );
            return;
        }

        Client_Agreement__c agreement = [
            SELECT Id,
                   Name,
                   Status__c,
                   Signed_File_Id__c,
                   Signed_Date__c,
                   Agreement_HTML__c,
                   Opportunity__c,
                   Opportunity__r.Name,
                   Opportunity__r.Email__c,
                   Opportunity__r.Lead_Name__c,
                   Opportunity__r.Supervisor_User_Email__c
            FROM Client_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];

        if (agreement.Status__c != 'Signed') {
            System.debug(
                'ClientAgreementSignedPdfJob skipped. ' +
                'Agreement is not Signed. Status=' +
                agreement.Status__c
            );
            return;
        }

        Blob signedPdfBlob =
            decodePdfBase64(signedPdfBase64);

        if (signedPdfBlob == null || signedPdfBlob.size() == 0) {
            System.debug(
                'Signed PDF generation failed: PDF blob is blank.'
            );
            return;
        }

        String pdfStart =
            EncodingUtil.base64Encode(signedPdfBlob).left(20);

        System.debug(
            'SIGNED PDF BLOB SIZE: ' +
            signedPdfBlob.size()
        );

        System.debug(
            'SIGNED PDF BLOB START: ' +
            pdfStart
        );

        /*
         * Validate that the submitted file is actually a PDF.
         *
         * PDF files encoded as Base64 begin with JVBER.
         */
        if (!pdfStart.startsWith('JVBER')) {
            System.debug(
                'Signed PDF is not a valid PDF. Base64 start=' +
                pdfStart
            );
            return;
        }

        String signedFileName =
            'Client_Agreement_' +
            agreement.Name +
            '_Signed.pdf';

        Id signedContentVersionId;

        /*
         * ---------------------------------------------------------
         * EXISTING FUNCTIONALITY
         * Save signed PDF against Opportunity.
         * ---------------------------------------------------------
         */
        try {

            signedContentVersionId =
                ClientAgreementFileService.savePdfFileFromBlob(
                    signedFileName,
                    signedPdfBlob,
                    agreement.Opportunity__c
                );

        } catch (Exception fileEx) {

            System.debug(
                'Signed PDF file save failed: ' +
                fileEx.getMessage()
            );

            System.debug(
                fileEx.getStackTraceString()
            );

            return;
        }

        /*
         * ---------------------------------------------------------
         * EXISTING FUNCTIONALITY
         * Store generated ContentVersion Id on Client Agreement.
         * ---------------------------------------------------------
         */
        try {

            Client_Agreement__c agreementToUpdate =
                new Client_Agreement__c();

            agreementToUpdate.Id =
                agreement.Id;

            agreementToUpdate.Signed_File_Id__c =
                String.valueOf(signedContentVersionId);

            update agreementToUpdate;

        } catch (Exception updateEx) {

            System.debug(
                'Signed_File_Id__c update failed: ' +
                updateEx.getMessage()
            );

            System.debug(
                updateEx.getStackTraceString()
            );
        }

        /*
         * ---------------------------------------------------------
         * EXISTING FUNCTIONALITY
         * Send signed agreement to supervisor.
         * ---------------------------------------------------------
         */
        try {

            sendSupervisorEmail(
                agreement,
                signedPdfBlob
            );

        } catch (Exception supervisorEmailEx) {

            System.debug(
                'Supervisor email failed after signed PDF generation: ' +
                supervisorEmailEx.getMessage()
            );

            System.debug(
                supervisorEmailEx.getStackTraceString()
            );
        }

        /*
         * ---------------------------------------------------------
         * NEW FUNCTIONALITY
         * Send signed agreement PDF to client.
         *
         * Kept in a separate try/catch intentionally.
         * A client-email problem must NOT affect:
         *
         * - Agreement signing
         * - Signed PDF creation
         * - Signed_File_Id__c update
         * - Supervisor notification
         * ---------------------------------------------------------
         */
        try {

            sendClientSignedAgreementEmail(
                agreement,
                signedPdfBlob
            );

        } catch (Exception clientEmailEx) {

            System.debug(
                'Client email failed after signed PDF generation: ' +
                clientEmailEx.getMessage()
            );

            System.debug(
                clientEmailEx.getStackTraceString()
            );
        }
    }

    /**
     * Converts the signed PDF Base64 received from the client
     * signing page back into a Blob.
     */
    private static Blob decodePdfBase64(String pdfBase64) {

        if (String.isBlank(pdfBase64)) {
            return null;
        }

        String cleanedBase64 =
            pdfBase64;

        /*
         * Handle values such as:
         *
         * data:application/pdf;base64,JVBER...
         */
        if (cleanedBase64.contains(',')) {
            cleanedBase64 =
                cleanedBase64.substringAfter(',');
        }

        try {

            return EncodingUtil.base64Decode(
                cleanedBase64
            );

        } catch (Exception e) {

            System.debug(
                'Invalid signed PDF Base64 content: ' +
                e.getMessage()
            );

            return null;
        }
    }

    /**
     * Existing supervisor notification.
     *
     * Existing behavior intentionally remains unchanged.
     */
    private static void sendSupervisorEmail(Client_Agreement__c agreement, Blob signedPdfBlob) {

        String supervisorEmail = agreement.Opportunity__r.Supervisor_User_Email__c;

        String clientEmail = agreement.Opportunity__r.Email__c;

        if (String.isBlank(supervisorEmail)) {

            throw new AuraHandledException(
                'Supervisor Email is missing on Opportunity.'
            );
        }

        if (
            signedPdfBlob == null ||
            signedPdfBlob.size() == 0
        ) {

            throw new AuraHandledException(
                'Signed PDF content is missing for supervisor email.'
            );
        }

        Id owdId = ClientAgreementEmailService.getOrgWideEmailAddressIdFromLabel();

        ClientAgreementEmailService.EmailRequest emailReq = new ClientAgreementEmailService.EmailRequest();

        emailReq.toAddress = supervisorEmail;

        emailReq.templateDeveloperName = System.Label.Client_Agreement_Supervisor_Email;

        emailReq.orgWideEmailAddressId = owdId;

        /*
         * Existing signed agreement attachment.
         */
        emailReq.attachmentFileName =
            'Client_Agreement_' +
            agreement.Name +
            '_Signed.pdf';

        emailReq.attachmentBase64 =
            EncodingUtil.base64Encode(
                signedPdfBlob
            );

        emailReq.attachmentContentType =
            'application/pdf';

        /*
         * Existing functionality:
         * Supporting files linked to Client_Agreement__c
         * continue to be included in the supervisor email.
         */
        List<String> supportingContentDocumentIds =
            getLinkedSupportingContentDocumentIds(
                agreement.Id
            );

        emailReq.entityAttachmentContentVersionIds = ClientAgreementAttachmentService.getLatestContentVersionIdsByContentDocumentIds(supportingContentDocumentIds);

        emailReq.mergeValues =
            new Map<String, String>{
                'CLIENT_EMAIL' =>
                    clientEmail,

                'SUPERVISOR_EMAIL' =>
                    supervisorEmail,

                'OPPORTUNITY_NAME' =>
                    agreement.Opportunity__r.Name,

                'SIGNED_DATE' =>
                    getSignedDateText(agreement)
            };

        ClientAgreementEmailService.sendEmail(emailReq);
    }

    /**
     * NEW:
     * Sends a copy of the completed signed agreement
     * directly to the client's Opportunity Email__c.
     *
     * Only the signed Client Agreement PDF is attached.
     *
     * Existing supervisor supporting-file behavior
     * is intentionally NOT copied here.
     */
    private static void sendClientSignedAgreementEmail(Client_Agreement__c agreement, Blob signedPdfBlob) {

        if (agreement == null) {

            throw new AuraHandledException(
                'Client Agreement is missing.'
            );
        }

        String clientEmail = agreement.Opportunity__r.Email__c;

        String leadName = String.isBlank(agreement.Opportunity__r.Lead_Name__c) ? 'Client': agreement.Opportunity__r.Lead_Name__c.trim();

        String supervisorEmail = agreement.Opportunity__r.Supervisor_User_Email__c;

        /*
         * Client email comes from the same Opportunity field
         * already used throughout the Client Agreement process.
         */
        if (String.isBlank(clientEmail)) {

            throw new AuraHandledException(
                'Client Email is missing on Opportunity.'
            );
        }

        if (
            signedPdfBlob == null ||
            signedPdfBlob.size() == 0
        ) {

            throw new AuraHandledException(
                'Signed PDF content is missing for client email.'
            );
        }

        Id owdId = ClientAgreementEmailService.getOrgWideEmailAddressIdFromLabel();

        ClientAgreementEmailService.EmailRequest emailReq = new ClientAgreementEmailService.EmailRequest();

        /*
         * NEW recipient:
         * Opportunity.Email__c
         */
        emailReq.toAddress = clientEmail;

        /*
         * New Lightning Email Template.
         *
         * Custom Label value should contain:
         * Client_Agreement_Signed_Client
         */
        emailReq.templateDeveloperName = System.Label.Client_Agreement_Signed_Client_Email;

        emailReq.orgWideEmailAddressId = owdId;

        /*
         * Attach the exact same signed PDF Blob that was:
         *
         * 1. Generated by the signing page
         * 2. Saved into Salesforce Files
         * 3. Sent to the supervisor
         */
        emailReq.attachmentFileName =
            'Client_Agreement_' +
            agreement.Name +
            '_Signed.pdf';

        emailReq.attachmentBase64 =
            EncodingUtil.base64Encode(
                signedPdfBlob
            );

        emailReq.attachmentContentType =
            'application/pdf';

        /*
         * No supporting files are added here.
         *
         * Client receives only the final signed agreement PDF.
         */
        emailReq.mergeValues = new Map<String, String>{
                'LEAD_NAME' =>
                    leadName,

                'CLIENT_EMAIL' =>
                    clientEmail,

                'SUPERVISOR_EMAIL' =>
                    supervisorEmail,

                'OPPORTUNITY_NAME' =>
                    agreement.Opportunity__r.Name,

                'AGREEMENT_NAME' =>
                    agreement.Name,

                'SIGNED_DATE' =>
                    getSignedDateText(agreement)
            };

        ClientAgreementEmailService.sendEmail(emailReq);
    }

    /**
     * Returns the actual agreement signed date.
     */
    private static String getSignedDateText(Client_Agreement__c agreement) {

        if (
            agreement == null ||
            agreement.Signed_Date__c == null
        ) {
            return '';
        }

        return agreement.Signed_Date__c.format(
            'dd-MMM-yyyy hh:mm a'
        );
    }

    /**
     * Existing functionality.
     *
     * Finds the selected supporting files that are linked
     * to Client_Agreement__c so they can continue to be
     * attached to the supervisor email.
     */
    private static List<String> getLinkedSupportingContentDocumentIds(Id agreementId) {

        List<String> contentDocumentIds = new List<String>();

        if (agreementId == null) {
            return contentDocumentIds;
        }

        for (
            ContentDocumentLink linkRecord : [
                SELECT ContentDocumentId,
                       ContentDocument.Title,
                       ContentDocument.FileType
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :agreementId
                LIMIT 50
            ]
        ) {

            if (linkRecord.ContentDocument == null) {
                continue;
            }

            /*
             * Avoid attaching previously generated
             * Client Agreement PDFs again.
             */
            if (
                !String.isBlank(
                    linkRecord.ContentDocument.Title
                ) &&
                linkRecord.ContentDocument.Title
                    .startsWith('Client_Agreement_')
            ) {
                continue;
            }

            String fileType =
                linkRecord.ContentDocument.FileType;

            if (String.isBlank(fileType)) {
                continue;
            }

            String upperFileType =
                fileType.toUpperCase();

            if (
                upperFileType == 'PDF' ||
                upperFileType == 'PNG' ||
                upperFileType == 'JPG' ||
                upperFileType == 'JPEG'
            ) {

                contentDocumentIds.add(
                    String.valueOf(
                        linkRecord.ContentDocumentId
                    )
                );
            }
        }

        return contentDocumentIds;
    }
}