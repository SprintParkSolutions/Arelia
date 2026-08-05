@RestResource(urlMapping='/mobileLogin/*')
global with sharing class MobileLoginService {

    @HttpPost
    global static LoginResponse login() {
        RestRequest req = RestContext.request;
        String body = req.requestBody == null ? null : req.requestBody.toString();

        Map<String, Object> inputData =
            String.isBlank(body)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(body);

        String username = (String) inputData.get('username');
        String password = (String) inputData.get('password');

        if (String.isBlank(username) || String.isBlank(password)) {
            return new LoginResponse(false, 'Username and password are required.', null, null);
        }

        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Email
            FROM Contact
            WHERE Email = :username
              AND Password__c = :password
            LIMIT 10
        ];

        if (contacts.isEmpty()) {
            return new LoginResponse(false, 'Invalid Username or Password', null, null);
        }

        Set<Id> contactIds = new Set<Id>();
        for (Contact contactRecord : contacts) {
            contactIds.add(contactRecord.Id);
        }

        Map<Id, Integer> projectCountByContact = new Map<Id, Integer>();
        for (AggregateResult row : [
            SELECT Client__c clientId, COUNT(Id) projectCount
            FROM Project__c
            WHERE Client__c IN :contactIds
            GROUP BY Client__c
        ]) {
            projectCountByContact.put(
                (Id) row.get('clientId'),
                (Integer) row.get('projectCount')
            );
        }

        Contact selected = contacts[0];
        Integer selectedProjectCount = projectCountByContact.containsKey(selected.Id)
            ? projectCountByContact.get(selected.Id)
            : 0;

        for (Contact candidate : contacts) {
            Integer candidateProjectCount = projectCountByContact.containsKey(candidate.Id)
                ? projectCountByContact.get(candidate.Id)
                : 0;

            if (candidateProjectCount > selectedProjectCount) {
                selected = candidate;
                selectedProjectCount = candidateProjectCount;
            }
        }

        String fullName = String.isBlank(selected.FirstName)
            ? selected.LastName
            : String.isBlank(selected.LastName)
                ? selected.FirstName
                : selected.FirstName + ' ' + selected.LastName;

        return new LoginResponse(true, 'Login Successful', selected.Id, fullName);
    }

    global class LoginResponse {
        public Boolean success;
        public String message;
        public String contactId;
        public String name;

        public LoginResponse(Boolean s, String m, String id, String n) {
            success = s;
            message = m;
            contactId = id;
            name = n;
        }
    }
}