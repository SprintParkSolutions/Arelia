@RestResource(urlMapping='/mobileClientProfile')
global without sharing class MobileClientProfileService {

    global class UserDTO {
        public String contactId;
        public String name;
        public String email;
        public String phone;
        public String company;
        public String projectId;
        public String projectName;
    }

    global class CaseDTO {
        public String caseId;
        public String subject;
        public String description;
        public String status;
        public String priority;
        public String category;
        public Date createdDate;
    }

    global class ResponseDTO {
        public Boolean success;
        public String message;
        public UserDTO user;
        public List<CaseDTO> cases;
    }

    @HttpPost
    global static ResponseDTO getClientProfile() {
        ResponseDTO resp = new ResponseDTO();
        resp.success = false;
        resp.cases = new List<CaseDTO>();

        try {
            String raw = RestContext.request.requestBody == null
                ? null
                : RestContext.request.requestBody.toString();
            Map<String, Object> input =
                String.isBlank(raw)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(raw);
            String contactId = (String) input.get('contactId');

            if (String.isBlank(contactId)) {
                resp.message = 'Missing Contact Id';
                return resp;
            }

            Contact c = [
                SELECT Id, Name, Email, Phone, Account.Name
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];

            List<Project__c> projects = [
                SELECT Id, Name
                FROM Project__c
                WHERE Client__c = :contactId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            UserDTO user = new UserDTO();
            user.contactId = c.Id;
            user.name = c.Name;
            user.email = c.Email;
            user.phone = c.Phone;
            user.company = c.Account != null ? c.Account.Name : 'Self';
            if (!projects.isEmpty()) {
                user.projectId = projects[0].Id;
                user.projectName = projects[0].Name;
            }
            resp.user = user;

            List<Case> caseList = [
                SELECT Id, Subject, Description, Status, Priority, Type, CreatedDate
                FROM Case
                WHERE ContactId = :contactId
                ORDER BY CreatedDate DESC
            ];

            for (Case cs : caseList) {
                CaseDTO dto = new CaseDTO();
                dto.caseId = cs.Id;
                dto.subject = cs.Subject;
                dto.description = cs.Description;
                dto.status = cs.Status;
                dto.priority = cs.Priority;
                dto.category = cs.Type;
                dto.createdDate = cs.CreatedDate.date();
                resp.cases.add(dto);
            }

            resp.success = true;
            resp.message = 'Success';
            return resp;
        } catch (Exception e) {
            resp.success = false;
            resp.message = e.getMessage();
            return resp;
        }
    }
}