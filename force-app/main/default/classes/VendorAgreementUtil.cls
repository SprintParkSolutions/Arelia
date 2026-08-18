/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementUtil
 * Author          : <YourName>
 * Created Date    : Jul 6, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 6, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 6, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public inherited sharing class VendorAgreementUtil {

    // public static Boolean isAreliaOpportunity(
    //     Opportunity opportunityRecord
    // ) {
    //     return opportunityRecord != null
    //         && opportunityRecord.RecordTypeId
    //             == VendorAgreementConstants.ARELIA_RECORD_TYPE_ID;
    // }

    public static Boolean isAreliaOpportunity(
        Opportunity opportunityRecord
    ) {
        return opportunityRecord != null
            && opportunityRecord.RecordType != null
            && opportunityRecord.RecordType.DeveloperName
                == VendorAgreementConstants.ARELIA_RECORD_TYPE_DEVELOPER_NAME;
    }

    public static String generateToken() {
        Blob randomKey = Crypto.generateAesKey(256);

        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', randomKey)
        );
    }

    public static String buildSigningUrl(Id agreementId) {
        String baseUrl =
            System.Label.Vendor_Agreement_Signing_Base_URL;

        if (String.isBlank(baseUrl)) {
            throw new AuraHandledException(
                'Custom Label Vendor_Agreement_Signing_Base_URL is not configured.'
            );
        }

        if (agreementId == null) {
            throw new AuraHandledException(
                'Vendor Agreement Id is required to build the signing link.'
            );
        }

        return baseUrl
            + '?agreementId='
            + EncodingUtil.urlEncode(
                String.valueOf(agreementId),
                'UTF-8'
            );
    }

    public static Id getOrgWideEmailAddressId() {
        String orgWideEmailAddressId = System.Label.Arelia_OWD_Id;

        if (String.isBlank(orgWideEmailAddressId)) {
            throw new AuraHandledException(
                'Custom Label Arelia_OWD_Id is not configured.'
            );
        }

        try {
            return Id.valueOf(orgWideEmailAddressId.trim());
        } catch (Exception exceptionValue) {
            throw new AuraHandledException(
                'Custom Label Arelia_OWD_Id must contain a valid Org-Wide Email Address Id.'
            );
        }
    }

    public static Id getEmailTemplateIdFromLabel(
        String templateIdValue,
        String labelName
    ) {
        if (String.isBlank(templateIdValue)) {
            throw new AuraHandledException(
                'Custom Label ' + labelName + ' is not configured.'
            );
        }

        try {
            return Id.valueOf(templateIdValue.trim());
        } catch (Exception idException) {
            throw new AuraHandledException(
                'Custom Label ' + labelName
                + ' does not contain a valid Lightning Email Template Id.'
            );
        }
    }

    public static String sanitizeHtml(String htmlValue) {
        if (String.isBlank(htmlValue)) {
            return '';
        }

        return htmlValue
            .replace('<script', '&lt;script')
            .replace('</script>', '&lt;/script&gt;');
    }

    public static String escapeHtml(String value) {
        return value == null
            ? ''
            : value.escapeHtml4();
    }
}