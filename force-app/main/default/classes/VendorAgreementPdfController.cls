/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementPdfController
 * Author          : <YourName>
 * Created Date    : Jun 26, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 26, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 26, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public without sharing class VendorAgreementPdfController {

    public Vendor_Agreement__c agreement { get; private set; }

    public VendorAgreementPdfController() {
        String agreementId = ApexPages.currentPage()
            .getParameters()
            .get('agreementId');

        if (String.isBlank(agreementId)) {
            return;
        }

        List<Vendor_Agreement__c> agreements = [
            SELECT Id,
                   Name,
                   Agreement_HTML__c
            FROM Vendor_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];

        if (!agreements.isEmpty()) {
            agreement = agreements[0];
        }
    }

    public String getAgreementHtml() {
        return agreement == null
            ? ''
            : agreement.Agreement_HTML__c;
    }
}