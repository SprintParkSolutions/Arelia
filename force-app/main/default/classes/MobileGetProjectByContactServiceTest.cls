@IsTest(SeeAllData=false)
private class MobileGetProjectByContactServiceTest {

    @isTest
    static void testGetProjectByContactReturnsProjectByContactId() {
        Contact testContact = TestDataUtility.createContact('MobileBuyer', 'mobilebuyer' + DateTime.now().getTime() + '@example.com', 'Test@1234');
        Project__c project = TestDataUtility.createProject('Mobile Contact Project', 75000, testContact.Id);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/getProjectByContact';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'contactId' => testContact.Id,
            'email' => ''
        }));

        RestContext.request = req;

        MobileGetProjectByContactService.ProjectDTO dto = MobileGetProjectByContactService.getProjectByContact();

        System.assertNotEquals(null, dto, 'DTO should be returned when a project exists for the contact');
        System.assertEquals(project.Id, dto.projectId);
        System.assertEquals(project.Name, dto.projectName);
    }

    @isTest
    static void testGetProjectByContactReturnsProjectByEmailWhenContactIdEmpty() {
        Contact testContact = TestDataUtility.createContact('MobileBuyerEmail', 'mobilebuyeremail' + DateTime.now().getTime() + '@example.com', 'Test@1234');
        Project__c project = TestDataUtility.createProject('Mobile Email Project', 80000, testContact.Id);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/getProjectByContact';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'contactId' => '',
            'email' => testContact.Email
        }));

        RestContext.request = req;

        MobileGetProjectByContactService.ProjectDTO dto = MobileGetProjectByContactService.getProjectByContact();

        System.assertNotEquals(null, dto, 'DTO should be returned when a project exists for the contact email');
        System.assertEquals(project.Id, dto.projectId);
        System.assertEquals(project.Name, dto.projectName);
    }

    @isTest
    static void testGetProjectByContactReturnsNullWhenNoInput() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/getProjectByContact';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'contactId' => '',
            'email' => ''
        }));

        RestContext.request = req;

        MobileGetProjectByContactService.ProjectDTO dto = MobileGetProjectByContactService.getProjectByContact();

        System.assertEquals(null, dto, 'No input should return null');
    }

    @isTest
    static void testGetProjectByContactReturnsNullWhenNoProjectFound() {
        Contact testContact = TestDataUtility.createContact('MobileBuyerMissing', 'mobilebuyermissing' + DateTime.now().getTime() + '@example.com', 'Test@1234');

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobile/getProjectByContact';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'contactId' => testContact.Id,
            'email' => testContact.Email
        }));

        RestContext.request = req;

        MobileGetProjectByContactService.ProjectDTO dto = MobileGetProjectByContactService.getProjectByContact();

        System.assertEquals(null, dto, 'When no project exists for the contact or email, service should return null');
    }
}