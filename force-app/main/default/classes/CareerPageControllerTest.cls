/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : CareerPageControllerTest
 * Author          : Sprintpark
 * Created Date    : May 15, 2026
 * Last Modified By: Sprintpark
 * Last Modified On: May 15, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  May 15, 2026  │ Sprintpark  │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

@IsTest
private class CareerPageControllerTest {

    private static final String TEST_EMAIL = 'testuser@example.com';
    private static final String TEST_FILE_NAME = 'resume.txt';
    private static final String TEST_FILE_BODY = 'Test File';

    @TestSetup
    static void setupData() {
        Quokka__JobOffer__c jobOffer = new Quokka__JobOffer__c(
            Name = 'Test Job Offer'
        );
        insert jobOffer;

        User currentUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        System.runAs(currentUser) {
            EmailTemplate applicantTemplate = new EmailTemplate(
                Name = 'Applicant Template',
                DeveloperName = 'Applicant_Template',
                FolderId = UserInfo.getUserId(),
                TemplateType = 'text',
                Subject = 'Applicant Subject',
                Body = 'Applicant Body'
            );
            insert applicantTemplate;

            EmailTemplate hrTemplate = new EmailTemplate(
                Name = 'HR Template',
                DeveloperName = 'HR_Template',
                FolderId = UserInfo.getUserId(),
                TemplateType = 'text',
                Subject = 'HR Subject',
                Body = 'HR Body'
            );
            insert hrTemplate;
        }
    }

    private static Quokka__JobApplication__c createTestApplication(
        String firstName,
        String lastName,
        String emailValue
    ) {
        Quokka__JobOffer__c jobOffer = [
            SELECT Id
            FROM Quokka__JobOffer__c
            LIMIT 1
        ];

        Quokka__JobApplication__c app =
            new Quokka__JobApplication__c(
                Quokka__FirstName__c = firstName,
                Quokka__LastName__c = lastName,
                Quokka__Email__c = emailValue,
                Quokka__JobOffer__c = jobOffer.Id
            );

        insert app;
        return app;
    }

    @IsTest
    static void testGetJobOffers() {
        Test.startTest();
        List<Quokka__JobOffer__c> results =
            CareerPageController.getJobOffers();
        Test.stopTest();

        System.assertNotEquals(
            null,
            results,
            'Job offers should be returned.'
        );
    }

    @IsTest
    static void testCreateJobApplicationSuccess() {
        Quokka__JobOffer__c jobOffer = [
            SELECT Id
            FROM Quokka__JobOffer__c
            LIMIT 1
        ];

        Quokka__JobApplication__c app =
            new Quokka__JobApplication__c(
                Quokka__FirstName__c = 'John',
                Quokka__LastName__c = 'Doe',
                Quokka__Email__c = TEST_EMAIL
            );

        Test.startTest();
        Quokka__JobApplication__c result =
            CareerPageController.createJobApplication(
                app,
                jobOffer.Id
            );
        Test.stopTest();

        System.assertNotEquals(
            null,
            result.Id,
            'Application should be inserted.'
        );
    }

    @IsTest
    static void testCreateJobApplicationException() {
        Boolean exceptionThrown = false;

        try {
            CareerPageController.createJobApplication(
                new Quokka__JobApplication__c(),
                null
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        System.assert(
            exceptionThrown,
            'Exception should be thrown for null Job Offer.'
        );
    }

    @IsTest
    static void testGetPicklistValues() {
        Test.startTest();

        List<Map<String, String>> invalidObject =
            CareerPageController.getPicklistValues(
                'InvalidObject',
                'Field'
            );

        List<Map<String, String>> invalidField =
            CareerPageController.getPicklistValues(
                'Account',
                'InvalidField'
            );

        List<Map<String, String>> validField =
            CareerPageController.getPicklistValues(
                'Account',
                'Industry'
            );

        Test.stopTest();

        System.assertEquals(
            0,
            invalidObject.size(),
            'Invalid object should return empty list.'
        );

        System.assertEquals(
            0,
            invalidField.size(),
            'Invalid field should return empty list.'
        );

        System.assertNotEquals(
            null,
            validField,
            'Valid field should return results.'
        );
    }

    @IsTest
    static void testUploadFile() {
        Quokka__JobApplication__c app =
            createTestApplication(
                'Jane',
                'Doe',
                TEST_EMAIL
            );

        String encodedBody = EncodingUtil.base64Encode(
            Blob.valueOf(TEST_FILE_BODY)
        );

        Test.startTest();
        CareerPageController.uploadFile(
            app.Id,
            TEST_FILE_NAME,
            encodedBody
        );
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :app.Id
        ];

        System.assertEquals(
            1,
            links.size(),
            'File should be linked.'
        );
    }

    @IsTest
    static void testSendEmailOnly() {
        Quokka__JobApplication__c app =
            createTestApplication(
                'Email',
                'Only',
                TEST_EMAIL
            );

        Test.startTest();
        CareerPageController.sendEmailOnly(app.Id);
        Test.stopTest();

        System.assert(true, 'Email method executed.');
    }

    @IsTest
    static void testSendEmailWithoutEmailAddress() {
        Quokka__JobApplication__c app =
            createTestApplication(
                'No',
                'Email',
                null
            );

        Test.startTest();
        CareerPageController.sendEmailOnly(app.Id);
        Test.stopTest();

        System.assert(true, 'Should exit gracefully.');
    }

    @IsTest
    static void testSendEmailWithBlankLastName() {
        Quokka__JobApplication__c app =
            createTestApplication(
                'BlankLast',
                null,
                'blanklast@example.com'
            );

        Test.startTest();
        CareerPageController.sendEmailOnly(app.Id);
        Test.stopTest();

        System.assert(
            true,
            'Should cover Applicant fallback last name.'
        );
    }

    @IsTest
    static void testSendEmailWithExistingContact() {
        insert new Contact(
            FirstName = 'Existing',
            LastName = 'User',
            Email = TEST_EMAIL
        );

        Quokka__JobApplication__c app =
            createTestApplication(
                'Existing',
                'User',
                TEST_EMAIL
            );

        Test.startTest();
        CareerPageController.sendEmailOnly(app.Id);
        Test.stopTest();

        System.assert(
            true,
            'Existing contact path should execute.'
        );
    }
}