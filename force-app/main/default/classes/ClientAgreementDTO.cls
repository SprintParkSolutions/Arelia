/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementDTO
 * Author          : <YourName>
 * Created Date    : Jun 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 10, 2026
 * Description     : DTO class for Client Agreement flow.
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 10, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class ClientAgreementDTO {
    public class InitResponse {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String clientEmail;
        @AuraEnabled public String supervisorEmail;
        @AuraEnabled public String agreementHtml;
        @AuraEnabled public List<SupportingFileDTO> supportingFiles;
    }

    public class PublicAgreementResponse {
        @AuraEnabled public Boolean valid;
        @AuraEnabled public String message;
        @AuraEnabled public Id agreementId;
        @AuraEnabled public String agreementHtml;
        @AuraEnabled public String clientEmail;
        @AuraEnabled public String supervisorEmail;
        @AuraEnabled public String status;
        @AuraEnabled public List<SupportingFileDTO> supportingFiles;
    }

    public class SupportingFileDTO {
        @AuraEnabled public String fileName;
        @AuraEnabled public String title;
        @AuraEnabled public String contentType;
        @AuraEnabled public String base64Data;
        @AuraEnabled public Boolean isImage;
        @AuraEnabled public Boolean isPdf;
        @AuraEnabled public String source;

        /*
         * Used to separate rich-text images from file-upload-section files.
         * Rich-text image HTML usually contains ContentVersionId or ContentDocumentId.
         */
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String contentVersionId;
    }
}