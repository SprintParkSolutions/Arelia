/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : AgreementPdfController
 * Author          : <YourName>
 * Created Date    : Jun 11, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 11, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 11, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public without sharing class AgreementPdfController {

    public Client_Agreement__c agreement { get; private set; }
    public Opportunity opp { get; private set; }

    public String agreementHtml { get; private set; }
    public String agreementPlainText { get; private set; }
    public String signatureDataUri { get; private set; }

    public Boolean hasSignature {
        get {
            return !String.isBlank(signatureDataUri);
        }
    }

    public Boolean hasSignatureImage {
        get {
            return !String.isBlank(signatureDataUri);
        }
    }

    public String documentTitle {
        get {
            if (agreement != null && agreement.Status__c == 'Signed') {
                return 'Signed Client Agreement';
            }
            return 'Client Agreement';
        }
    }

    public String generatedDateText {
        get {
            return Datetime.now().format('dd-MMM-yyyy hh:mm a');
        }
    }

    public String signedDateText {
        get {
            if (agreement == null || agreement.Signed_Date__c == null) {
                return '';
            }
            return agreement.Signed_Date__c.format('dd-MMM-yyyy hh:mm a');
        }
    }

    public AgreementPdfController() {
        Id agreementId = getAgreementIdFromPage();

        if (agreementId == null) {
            throw new AuraHandledException('Agreement Id is required.');
        }

        loadAgreement(agreementId);
        prepareSignature();
        prepareAgreementHtml();

        /*
         * Do not load Opportunity images yet.
         * First make sure the basic Visualforce PDF renders correctly.
         * We will add image/exhibit rendering back after the PDF is no longer blank.
         */
    }

    private Id getAgreementIdFromPage() {
        String idParam = ApexPages.currentPage().getParameters().get('id');

        if (String.isBlank(idParam)) {
            return null;
        }

        return (Id) idParam;
    }

    private void loadAgreement(Id agreementId) {
        agreement = [
            SELECT Id,
                   Name,
                   Status__c,
                   Agreement_HTML__c,
                   Signature_Base64__c,
                   Signed_Date__c,
                   PDF_File_Id__c,
                   Signed_File_Id__c,
                   Opportunity__c,
                   Opportunity__r.Id,
                   Opportunity__r.Name,
                   Opportunity__r.Email__c,
                   Opportunity__r.Supervisor_User_Email__c
            FROM Client_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];

        opp = agreement.Opportunity__r;
    }

    private void prepareAgreementHtml() {
        if (String.isBlank(agreement.Agreement_HTML__c)) {
            agreementHtml = '<p>No agreement body found.</p>';
            agreementPlainText = 'No agreement body found.';
            return;
        }

        agreementHtml = sanitizeAgreementHtmlForPdf(agreement.Agreement_HTML__c);
        agreementPlainText = htmlToPlainText(agreement.Agreement_HTML__c);
    }

    private String sanitizeAgreementHtmlForPdf(String html) {
        if (String.isBlank(html)) {
            return '';
        }

        String cleaned = html;

        cleaned = cleaned.replaceAll('(?is)<script[\\s\\S]*?</script>', '');
        cleaned = cleaned.replaceAll('(?is)<style[\\s\\S]*?</style>', '');
        cleaned = cleaned.replaceAll('(?is)<iframe[\\s\\S]*?</iframe>', '');
        cleaned = cleaned.replaceAll('(?is)<object[\\s\\S]*?</object>', '');
        cleaned = cleaned.replaceAll('(?is)<embed[\\s\\S]*?>', '');

        return cleaned;
    }

    private String htmlToPlainText(String html) {
        if (String.isBlank(html)) {
            return '';
        }

        String text = html;

        text = text.replaceAll('(?i)<br\\s*/?>', '\n');
        text = text.replaceAll('(?i)</p>', '\n\n');
        text = text.replaceAll('(?i)</div>', '\n');
        text = text.replaceAll('(?i)</h1>', '\n\n');
        text = text.replaceAll('(?i)</h2>', '\n\n');
        text = text.replaceAll('(?i)</h3>', '\n\n');
        text = text.replaceAll('(?i)<li>', '• ');
        text = text.replaceAll('(?i)</li>', '\n');

        text = text.replaceAll('(?is)<script[\\s\\S]*?</script>', '');
        text = text.replaceAll('(?is)<style[\\s\\S]*?</style>', '');

        /*
         * Remove all remaining HTML tags.
         * This makes the diagnostic PDF stable.
         */
        text = text.replaceAll('(?is)<[^>]+>', '');

        text = text
            .replace('&nbsp;', ' ')
            .replace('&amp;', '&')
            .replace('&lt;', '<')
            .replace('&gt;', '>')
            .replace('&quot;', '"')
            .replace('&#39;', '\'');

        text = text.replaceAll('\\n{3,}', '\n\n');

        return text.trim();
    }

    private void prepareSignature() {
        signatureDataUri = null;

        if (String.isBlank(agreement.Signature_Base64__c)) {
            return;
        }

        String sig = agreement.Signature_Base64__c;

        if (sig.startsWith('data:image')) {
            signatureDataUri = sig;
        } else {
            signatureDataUri = 'data:image/png;base64,' + sig;
        }
    }
}