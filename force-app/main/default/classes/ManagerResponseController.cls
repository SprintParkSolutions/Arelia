public without sharing class ManagerResponseController {
    public String message {get;set;}
    public Boolean success {get;set;}

    public void initAction() {
        String recId = ApexPages.currentPage().getParameters().get('id');
        String action = ApexPages.currentPage().getParameters().get('action');

        if(String.isNotBlank(recId) && String.isNotBlank(action)) {
            try {
                Architecture_Design__c ad = [SELECT Id, Manager_Approval__c, Manager_Comments__c FROM Architecture_Design__c WHERE Id = :recId LIMIT 1];
                
                if(action == 'Approve') {
                    ad.Manager_Approval__c = true;
                    ad.Manager_Comments__c = 'Approved via Email Link';
                    message = 'Thank you! You have successfully approved the design.';
                } else {
                    ad.Manager_Approval__c = false;
                    ad.Manager_Comments__c = 'Manager requested changes via Email Link';
                    message = 'Thank you. A request for changes has been logged.';
                }
                update ad;
                success = true;
            } catch(Exception e) {
                message = 'Error processing request: ' + e.getMessage();
                success = false;
            }
        }
    }
}