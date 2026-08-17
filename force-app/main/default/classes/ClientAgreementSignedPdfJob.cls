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

public without sharing class ClientAgreementSignedPdfJob implements Queueable {

    private Id agreementId;
    private String signedPdfBase64;

    public ClientAgreementSignedPdfJob(Id agreementId) {
        this.agreementId = agreementId;
    }

    public ClientAgreementSignedPdfJob(Id agreementId, String signedPdfBase64) {
        this.agreementId = agreementId;
        this.signedPdfBase64 = signedPdfBase64;
    }

    public void execute(QueueableContext context) {
        if (agreementId == null) {
            System.debug('ClientAgreementSignedPdfJob failed: agreementId is null.');
            return;
        }

        Client_Agreement__c agreement = [
            SELECT Id,
                   Name,
                   Status__c,
                   Signed_File_Id__c,
                   Agreement_HTML__c,
                   Opportunity__c,
                   Opportunity__r.Name,
                   Opportunity__r.Email__c,
                   Opportunity__r.Supervisor_User_Email__c
            FROM Client_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];

        if (agreement.Status__c != 'Signed') {
            System.debug('ClientAgreementSignedPdfJob skipped. Agreement is not Signed. Status=' + agreement.Status__c);
            return;
        }

        Blob signedPdfBlob = decodePdfBase64(signedPdfBase64);

        if (signedPdfBlob == null || signedPdfBlob.size() == 0) {
            System.debug('Signed PDF generation failed: PDF blob is blank.');
            return;
        }

        String pdfStart = EncodingUtil.base64Encode(signedPdfBlob).left(20);
        System.debug('SIGNED PDF BLOB SIZE: ' + signedPdfBlob.size());
        System.debug('SIGNED PDF BLOB START: ' + pdfStart);

        if (!pdfStart.startsWith('JVBER')) {
            System.debug('Signed PDF is not a valid PDF. Base64 start=' + pdfStart);
            return;
        }

        String signedFileName = 'Client_Agreement_' + agreement.Name + '_Signed.pdf';

        Id signedContentVersionId;

        try {
            signedContentVersionId = ClientAgreementFileService.savePdfFileFromBlob(
                signedFileName,
                signedPdfBlob,
                agreement.Opportunity__c
            );
        } catch (Exception fileEx) {
            System.debug('Signed PDF file save failed: ' + fileEx.getMessage());
            System.debug(fileEx.getStackTraceString());
            return;
        }

        try {
            Client_Agreement__c agreementToUpdate = new Client_Agreement__c();
            agreementToUpdate.Id = agreement.Id;
            agreementToUpdate.Signed_File_Id__c = String.valueOf(signedContentVersionId);
            update agreementToUpdate;
        } catch (Exception updateEx) {
            System.debug('Signed_File_Id__c update failed: ' + updateEx.getMessage());
            System.debug(updateEx.getStackTraceString());
        }

        try {
            sendSupervisorEmail(agreement, signedPdfBlob);
        } catch (Exception emailEx) {
            System.debug('Supervisor email failed after signed PDF generation: ' + emailEx.getMessage());
            System.debug(emailEx.getStackTraceString());
        }
    }

    private static Blob decodePdfBase64(String pdfBase64) {
        if (String.isBlank(pdfBase64)) {
            return null;
        }

        String cleanedBase64 = pdfBase64;

        if (cleanedBase64.contains(',')) {
            cleanedBase64 = cleanedBase64.substringAfter(',');
        }

        try {
            return EncodingUtil.base64Decode(cleanedBase64);
        } catch (Exception e) {
            System.debug('Invalid signed PDF Base64 content: ' + e.getMessage());
            return null;
        }
    }

    private static void sendSupervisorEmail(
        Client_Agreement__c agreement,
        Blob signedPdfBlob
    ) {
        String supervisorEmail = agreement.Opportunity__r.Supervisor_User_Email__c;
        String clientEmail = agreement.Opportunity__r.Email__c;

        if (String.isBlank(supervisorEmail)) {
            throw new AuraHandledException('Supervisor Email is missing on Opportunity.');
        }

        if (signedPdfBlob == null || signedPdfBlob.size() == 0) {
            throw new AuraHandledException('Signed PDF content is missing for supervisor email.');
        }

        Id owdId = ClientAgreementEmailService.getOrgWideEmailAddressIdFromLabel();

        ClientAgreementEmailService.EmailRequest emailReq =
            new ClientAgreementEmailService.EmailRequest();

        emailReq.toAddress = supervisorEmail;
        emailReq.templateDeveloperName =
            System.Label.Client_Agreement_Supervisor_Email;
        emailReq.orgWideEmailAddressId = owdId;

        /*
         * Keep signed agreement PDF as raw attachment.
         * This is already working.
         */
        emailReq.attachmentFileName =
            'Client_Agreement_' + agreement.Name + '_Signed.pdf';

        emailReq.attachmentBase64 = EncodingUtil.base64Encode(signedPdfBlob);
        emailReq.attachmentContentType = 'application/pdf';

        /*
         * Important change:
         * Supporting files linked to Client_Agreement__c are attached by ContentVersion Id.
         * This avoids skipping larger PDFs and keeps correct PDF/image format.
         */
        List<String> supportingContentDocumentIds =
            getLinkedSupportingContentDocumentIds(agreement.Id);

        emailReq.entityAttachmentContentVersionIds =
            ClientAgreementAttachmentService.getLatestContentVersionIdsByContentDocumentIds(
                supportingContentDocumentIds
            );

        emailReq.mergeValues = new Map<String, String>{
            'CLIENT_EMAIL' => clientEmail,
            'SUPERVISOR_EMAIL' => supervisorEmail,
            'OPPORTUNITY_NAME' => agreement.Opportunity__r.Name,
            'SIGNED_DATE' => String.valueOf(System.now())
        };

        ClientAgreementEmailService.sendEmail(emailReq);
    }

    private static List<String> getLinkedSupportingContentDocumentIds(Id agreementId) {
        List<String> contentDocumentIds = new List<String>();

        if (agreementId == null) {
            return contentDocumentIds;
        }

        for (ContentDocumentLink linkRecord : [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :agreementId
            LIMIT 50
        ]) {
            if (linkRecord.ContentDocument == null) {
                continue;
            }

            /*
             * Avoid attaching generated agreement PDFs again.
             */
            if (!String.isBlank(linkRecord.ContentDocument.Title)
                && linkRecord.ContentDocument.Title.startsWith('Client_Agreement_')) {
                continue;
            }

            String fileType = linkRecord.ContentDocument.FileType;

            if (String.isBlank(fileType)) {
                continue;
            }

            String upperFileType = fileType.toUpperCase();

            if (upperFileType == 'PDF'
                || upperFileType == 'PNG'
                || upperFileType == 'JPG'
                || upperFileType == 'JPEG') {
                contentDocumentIds.add(String.valueOf(linkRecord.ContentDocumentId));
            }
        }

        return contentDocumentIds;
    }
}