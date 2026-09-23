@IsTest
private class RegistrationLeadRestControllerTest {

    private static RegistrationLeadRestController.LeadResponse callRegisterLead(String requestBody) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/registration/lead';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = Blob.valueOf(requestBody);

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        return RegistrationLeadRestController.registerLead();
    }

    @IsTest
    static void testRegisterLeadSuccess() {
        String uniqueKey = String.valueOf(DateTime.now().getTime());

        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'Test',
            'lastName' => 'Mobile User',
            'email' => 'mobileuser' + uniqueKey + '@test.com',
            'phone' => '9999999999',
            'companyName' => 'Arelia App User',

            'company' => 'Arelia App User',
            'budget' => '100000',
            'description' => 'Test lead from mobile app registration',
            'siteLocation' => 'Hyderabad',
            'type' => 'Home',
            'projectScope' => 'Full Home Interiors',
            'projectType' => 'Home'
        };

        Test.startTest();
        RegistrationLeadRestController.LeadResponse response =
            callRegisterLead(JSON.serialize(payload));
        Test.stopTest();

        System.debug('REGISTRATION LEAD RESPONSE SUCCESS: ' + response.success);
        System.debug('REGISTRATION LEAD RESPONSE LEAD ID: ' + response.leadId);
        System.debug('REGISTRATION LEAD RESPONSE MESSAGE: ' + response.message);

        System.assertEquals(
            true,
            response.success,
            'Registration failed. Actual error is: ' + response.message
        );

        System.assertNotEquals(null, response.leadId);

        Lead createdLead = [
            SELECT Id, FirstName, LastName, Email, Phone, Company
            FROM Lead
            WHERE Id = :response.leadId
            LIMIT 1
        ];

        System.assertEquals('Test', createdLead.FirstName);
        System.assertEquals('Mobile User', createdLead.LastName);
    }

    @IsTest
    static void testRegisterLeadInvalidJsonException() {
        Test.startTest();
        RegistrationLeadRestController.LeadResponse response =
            callRegisterLead('{ invalid json');
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals(null, response.leadId);
        System.assertNotEquals(null, response.message);
    }

    @IsTest
    static void testLeadResponseConstructor() {
        RegistrationLeadRestController.LeadResponse response =
            new RegistrationLeadRestController.LeadResponse(
                true,
                null,
                'Test Message'
            );

        System.assertEquals(true, response.success);
        System.assertEquals(null, response.leadId);
        System.assertEquals('Test Message', response.message);
    }
}