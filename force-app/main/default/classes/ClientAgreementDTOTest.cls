/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementDTOTest
 * Author          : <YourName>
 * Created Date    : Jul 14, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 14, 2026
 * Description     : Tests the ClientAgreementDTO wrapper classes and verifies
 *                   that all DTO properties can be populated and retrieved.
 *
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 14, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@IsTest
private class ClientAgreementDTOTest {

    private static final String OPPORTUNITY_NAME = 'Test Arelia Opportunity';
    private static final String CLIENT_EMAIL = 'client@example.com';
    private static final String SUPERVISOR_EMAIL = 'supervisor@example.com';
    private static final String AGREEMENT_HTML = '<p>Client Agreement</p>';
    private static final String FILE_BASE64 = 'VGVzdCBGaWxlIENvbnRlbnQ=';

    @IsTest
    static void initResponseShouldStoreAllValues() {
        Id opportunityId = UserInfo.getUserId();

        ClientAgreementDTO.SupportingFileDTO supportingFile =
            buildSupportingFile();

        ClientAgreementDTO.InitResponse response =
            new ClientAgreementDTO.InitResponse();

        response.opportunityId = opportunityId;
        response.opportunityName = OPPORTUNITY_NAME;
        response.clientEmail = CLIENT_EMAIL;
        response.supervisorEmail = SUPERVISOR_EMAIL;
        response.agreementHtml = AGREEMENT_HTML;
        response.supportingFiles =
            new List<ClientAgreementDTO.SupportingFileDTO>{
                supportingFile
            };

        System.assertEquals(
            opportunityId,
            response.opportunityId,
            'Opportunity Id should be stored.'
        );
        System.assertEquals(
            OPPORTUNITY_NAME,
            response.opportunityName,
            'Opportunity name should be stored.'
        );
        System.assertEquals(
            CLIENT_EMAIL,
            response.clientEmail,
            'Client email should be stored.'
        );
        System.assertEquals(
            SUPERVISOR_EMAIL,
            response.supervisorEmail,
            'Supervisor email should be stored.'
        );
        System.assertEquals(
            AGREEMENT_HTML,
            response.agreementHtml,
            'Agreement HTML should be stored.'
        );
        System.assertEquals(
            1,
            response.supportingFiles.size(),
            'One supporting file should be stored.'
        );
        System.assertEquals(
            supportingFile,
            response.supportingFiles[0],
            'The expected supporting file should be returned.'
        );
    }

    @IsTest
    static void publicAgreementResponseShouldStoreAllValues() {
        Id agreementId = UserInfo.getUserId();

        ClientAgreementDTO.SupportingFileDTO supportingFile =
            buildSupportingFile();

        ClientAgreementDTO.PublicAgreementResponse response =
            new ClientAgreementDTO.PublicAgreementResponse();

        response.valid = true;
        response.message = 'Success';
        response.agreementId = agreementId;
        response.agreementHtml = AGREEMENT_HTML;
        response.clientEmail = CLIENT_EMAIL;
        response.supervisorEmail = SUPERVISOR_EMAIL;
        response.status = 'Sent';
        response.supportingFiles =
            new List<ClientAgreementDTO.SupportingFileDTO>{
                supportingFile
            };

        System.assertEquals(
            true,
            response.valid,
            'Response should be valid.'
        );
        System.assertEquals(
            'Success',
            response.message,
            'Response message should be stored.'
        );
        System.assertEquals(
            agreementId,
            response.agreementId,
            'Agreement Id should be stored.'
        );
        System.assertEquals(
            AGREEMENT_HTML,
            response.agreementHtml,
            'Agreement HTML should be stored.'
        );
        System.assertEquals(
            CLIENT_EMAIL,
            response.clientEmail,
            'Client email should be stored.'
        );
        System.assertEquals(
            SUPERVISOR_EMAIL,
            response.supervisorEmail,
            'Supervisor email should be stored.'
        );
        System.assertEquals(
            'Sent',
            response.status,
            'Agreement status should be stored.'
        );
        System.assertEquals(
            1,
            response.supportingFiles.size(),
            'One supporting file should be stored.'
        );
    }

    @IsTest
    static void supportingFileDtoShouldStoreAllValues() {
        ClientAgreementDTO.SupportingFileDTO supportingFile =
            buildSupportingFile();

        System.assertEquals(
            'Floor Plan.pdf',
            supportingFile.fileName,
            'File name should be stored.'
        );
        System.assertEquals(
            'Floor Plan',
            supportingFile.title,
            'File title should be stored.'
        );
        System.assertEquals(
            'application/pdf',
            supportingFile.contentType,
            'Content type should be stored.'
        );
        System.assertEquals(
            FILE_BASE64,
            supportingFile.base64Data,
            'Base64 file content should be stored.'
        );
        System.assertEquals(
            false,
            supportingFile.isImage,
            'PDF file should not be marked as an image.'
        );
        System.assertEquals(
            true,
            supportingFile.isPdf,
            'PDF file should be marked as a PDF.'
        );
        System.assertEquals(
            'Salesforce File',
            supportingFile.source,
            'File source should be stored.'
        );
        System.assertEquals(
            '069000000000001AAA',
            supportingFile.contentDocumentId,
            'Content Document Id should be stored.'
        );
        System.assertEquals(
            '068000000000001AAA',
            supportingFile.contentVersionId,
            'Content Version Id should be stored.'
        );
    }

    @IsTest
    static void dtoPropertiesShouldAllowNullValues() {
        ClientAgreementDTO.InitResponse initResponse =
            new ClientAgreementDTO.InitResponse();

        ClientAgreementDTO.PublicAgreementResponse publicResponse =
            new ClientAgreementDTO.PublicAgreementResponse();

        ClientAgreementDTO.SupportingFileDTO supportingFile =
            new ClientAgreementDTO.SupportingFileDTO();

        System.assertEquals(
            null,
            initResponse.opportunityId,
            'Unassigned Opportunity Id should be null.'
        );
        System.assertEquals(
            null,
            initResponse.supportingFiles,
            'Unassigned supporting files should be null.'
        );
        System.assertEquals(
            null,
            publicResponse.valid,
            'Unassigned valid flag should be null.'
        );
        System.assertEquals(
            null,
            publicResponse.agreementId,
            'Unassigned Agreement Id should be null.'
        );
        System.assertEquals(
            null,
            supportingFile.fileName,
            'Unassigned file name should be null.'
        );
        System.assertEquals(
            null,
            supportingFile.isPdf,
            'Unassigned PDF flag should be null.'
        );
    }

    @IsTest
    static void dtoClassesShouldSerializeToJson() {
        ClientAgreementDTO.InitResponse initResponse =
            new ClientAgreementDTO.InitResponse();

        initResponse.opportunityId = UserInfo.getUserId();
        initResponse.opportunityName = OPPORTUNITY_NAME;
        initResponse.clientEmail = CLIENT_EMAIL;
        initResponse.supervisorEmail = SUPERVISOR_EMAIL;
        initResponse.agreementHtml = AGREEMENT_HTML;
        initResponse.supportingFiles =
            new List<ClientAgreementDTO.SupportingFileDTO>{
                buildSupportingFile()
            };

        ClientAgreementDTO.PublicAgreementResponse publicResponse =
            new ClientAgreementDTO.PublicAgreementResponse();

        publicResponse.valid = true;
        publicResponse.message = 'Success';
        publicResponse.agreementId = UserInfo.getUserId();
        publicResponse.agreementHtml = AGREEMENT_HTML;
        publicResponse.clientEmail = CLIENT_EMAIL;
        publicResponse.supervisorEmail = SUPERVISOR_EMAIL;
        publicResponse.status = 'Sent';
        publicResponse.supportingFiles = initResponse.supportingFiles;

        String initJson = JSON.serialize(initResponse);
        String publicJson = JSON.serialize(publicResponse);

        System.assert(
            initJson.contains(OPPORTUNITY_NAME),
            'Serialized initialization response should contain the opportunity name.'
        );
        System.assert(
            initJson.contains('supportingFiles'),
            'Serialized initialization response should contain supporting files.'
        );
        System.assert(
            publicJson.contains('"valid":true'),
            'Serialized public response should contain the valid flag.'
        );
        System.assert(
            publicJson.contains('"status":"Sent"'),
            'Serialized public response should contain the agreement status.'
        );
    }

    private static ClientAgreementDTO.SupportingFileDTO buildSupportingFile() {
        ClientAgreementDTO.SupportingFileDTO supportingFile =
            new ClientAgreementDTO.SupportingFileDTO();

        supportingFile.fileName = 'Floor Plan.pdf';
        supportingFile.title = 'Floor Plan';
        supportingFile.contentType = 'application/pdf';
        supportingFile.base64Data = FILE_BASE64;
        supportingFile.isImage = false;
        supportingFile.isPdf = true;
        supportingFile.source = 'Salesforce File';
        supportingFile.contentDocumentId = '069000000000001AAA';
        supportingFile.contentVersionId = '068000000000001AAA';

        return supportingFile;
    }
}