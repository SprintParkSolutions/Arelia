@RestResource(urlMapping='/mobileChatbotfinal')
global with sharing class MobileChatbot {

    @HttpPost
    global static ChatbotResponse chat() {

        Map<String,Object> input =
            (Map<String,Object>) JSON.deserializeUntyped(RestContext.request.requestBody.toString());

        String message   = (String) input.get('message');
        String contactId = (String) input.get('contactId');

        if(String.isBlank(contactId)){
            return new ChatbotResponse('Missing Contact Id');
        }

        String msgLower = message.toLowerCase();
        String reply;

        // PROJECT / STATUS / VENDORS
        if(msgLower.contains('status') || msgLower.contains('project') || msgLower.contains('vendor')){
            reply = getProjectStatusFromService(contactId);
        }
        else if(msgLower.contains('timeline')){
            reply = getTimelineFromService(contactId);
        }
        else if(msgLower.contains('payment')){
            reply = getPaymentsFromService(contactId);
        }
        else if(msgLower.contains('document') || msgLower.contains('file')){
            reply = getDocuments(contactId);
        }
        else if(msgLower.contains('dashboard')){
            reply = getDashboardFromService(contactId);
        }
        else{
            reply = 'Hi 😊 You can ask me about:\n• Project Status\n• Payments\n• Timeline\n• Documents\n• Dashboard\n• My Project';
        }

        return new ChatbotResponse(reply);
    }

    // =====================================================
    // 🟢 PROJECT STATUS SERVICE (FIXED)
    // =====================================================
    private static String getProjectStatusFromService(String contactId){

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/mobileProjectStatus';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"contactId":"'+contactId+'"}');

        RestContext.request = req;
        RestContext.response = res;

        MobileProjectStatusService.ResponseDTO resp =
            MobileProjectStatusService.getProjects();

        if(resp.projects.isEmpty()) return 'No project found.';

        MobileProjectStatusService.ProjectDTO p = resp.projects[0];

        String msg = '🏡 Project: ' + p.projectName + '\n';
        msg += 'Status: ' + p.projectStatus + '\n';
        msg += 'Completion: ' + p.completionPercentage + '%\n\n';

        msg += '👷 Vendors Progress:\n\n';

        for(MobileProjectStatusService.VendorDTO v : p.vendors){
            msg += '• ' + v.vendorName + ' (' + v.vendorCategory + ')\n';
            msg += 'Progress: ' + v.completionPercentage + '%\n';
            msg += 'Remaining Tasks: ' + v.remainingTasks + '%\n\n';
        }

        return msg;
    }

    // =====================================================
    // 🟢 TIMELINE SERVICE (NEW)
    // =====================================================
    private static String getTimelineFromService(String contactId){

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/mobileProjectTimeline';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"contactId":"'+contactId+'"}');

        RestContext.request = req;
        RestContext.response = res;

        MobileProjectTimelineService.ResponseDTO resp =
            MobileProjectTimelineService.getProjectTimeline();

        if(resp.timelines.isEmpty()) return 'No timeline found.';

        MobileProjectTimelineService.TimelineDTO t = resp.timelines[0];

        return '🕒 Timeline\n\nProject: ' + t.projectName +
               '\nStart: ' + t.projectStartDate +
               '\nEstimated End: ' + t.estimatedEndDate +
               '\nStatus: ' + t.projectStatus;
    }

    // =====================================================
    // 🟢 PAYMENT SERVICE (FIXED BIG TIME)
    // =====================================================
    private static String getPaymentsFromService(String contactId){

        // first get project name
        List<Project__c> projects = [
            SELECT Name FROM Project__c WHERE Client__c = :contactId LIMIT 1
        ];
        if(projects.isEmpty()) return 'No project found.';

        String projectName = projects[0].Name;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/payment-terms';
        req.httpMethod = 'GET';
        req.addParameter('projectName', projectName);

        RestContext.request = req;
        RestContext.response = res;

        List<PaymentTermRestService.PaymentTermDTO> terms =
            PaymentTermRestService.getTerms();

        if(terms.isEmpty()) return 'No payment milestones found.';

        Integer paid = 0;
        Integer pending = 0;

        for(PaymentTermRestService.PaymentTermDTO t : terms){
            if(t.paymentReceived) paid++; else pending++;
        }

        String msg = '💰 Payment Summary\n\n';
        msg += '✅ Completed: ' + paid + '\n';
        msg += '⏳ Pending: ' + pending + '\n\n';

        for(PaymentTermRestService.PaymentTermDTO t : terms){
            msg += '• ' + t.label + ' (' + t.percentage + '%)\n';
            msg += 'Due: ' + t.dueDate + '\n';
            msg += 'Status: ' + (t.paymentReceived ? 'Paid' : 'Pending') + '\n\n';
        }

        return msg;
    }

    // =====================================================
    // 🟢 DASHBOARD SERVICE (FIXED)
    // =====================================================
    private static String getDashboardFromService(String contactId){

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/mobile/dashboard';
        req.httpMethod = 'GET';
        req.addParameter('contactId', contactId);

        RestContext.request = req;
        RestContext.response = res;

        MobileDashboardService.DashboardResponse d =
            MobileDashboardService.getDashboard();

        return '📊 Dashboard\n\nProject: ' + d.projectName +
               '\nBudget: ₹' + d.budget +
               '\nCompletion: ' + d.progress + '%';
    }

    // =====================================================
    private static String getDocuments(String contactId){
        Integer countDocs = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN (SELECT Id FROM Project__c WHERE Client__c = :contactId)
        ];
        return '📂 You have ' + countDocs + ' project documents available.';
    }

    global class ChatbotResponse{
        public String reply;
        public ChatbotResponse(String r){ reply = r; }
    }
}