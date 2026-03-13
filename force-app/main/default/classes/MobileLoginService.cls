@RestResource(urlMapping='/mobileLogin/*')
global with sharing class MobileLoginService {
 
    @HttpPost
    global static LoginResponse login() {
 
        RestRequest req = RestContext.request;
        String body = req.requestBody.toString();
 
        Map<String, Object> inputData =
            (Map<String, Object>) JSON.deserializeUntyped(body);
 
        String username = (String) inputData.get('username');
        String password = (String) inputData.get('password');
 
        Contact c;
 
        try {
            c = [
                SELECT Id, FirstName, LastName, Email
                FROM Contact
                WHERE Email = :username
                AND Password__c = :password
                LIMIT 1
            ];
        } catch (Exception e) {
            return new LoginResponse(
                false,
                'Invalid Username or Password',
                null,
                null,
                null
            );
        }
 
        // 🔥 IMPORTANT ADDITION
        String sessionId = UserInfo.getSessionId();
 
        return new LoginResponse(
            true,
            'Login Successful',
            c.Id,
            c.FirstName + ' ' + c.LastName,
            sessionId
        );
    }
 
    global class LoginResponse {
        public Boolean success;
        public String message;
        public String contactId;
        public String name;
        public String sessionId; // 🔥 NEW
 
        public LoginResponse(
            Boolean s,
            String m,
            String id,
            String n,
            String sid
        ) {
            success = s;
            message = m;
            contactId = id;
            name = n;
            sessionId = sid;
        }
    }
}