public without sharing class PublicApprovalController {
    public Boolean approved {get; set;}
    public Boolean rejected {get; set;}
    public Boolean hasError {get; set;}
    public String errorMessage {get; set;}
    public Id quoteId {get; set;} 
    
    // VARIABLES FOR REJECTION INPUT
    public String rejectionReason {get; set;}
    public Boolean isRejecting {get; set;} 

    public PublicApprovalController() {
        approved = false;
        rejected = false;
        hasError = false;
        isRejecting = false;
    }

    // --- JS BRIDGE ---
    public void setRecordIdFromClient() {
        try {
            String idParam = ApexPages.currentPage().getParameters().get('pId');
            if (String.isNotBlank(idParam)) {
                quoteId = (Id)idParam;
                hasError = false;
            } else {
                hasError = true;
                errorMessage = 'Error: ID could not be retrieved from the URL.';
            }
        } catch(Exception e) {
            hasError = true;
            errorMessage = 'Invalid ID format.';
        }
    }

    public PageReference doApprove() {
        if (quoteId == null) {
            hasError = true; errorMessage = 'System Error: Record ID is lost.'; return null;
        }
        try {
            QuotationService.processApproval(quoteId);
            approved = true;
        } catch(Exception e) {
            hasError = true; errorMessage = e.getMessage();
        }
        return null;
    }

    // --- REJECTION LOGIC ---
    
    // 1. Show Input Box
    public PageReference enableRejectMode() {
        isRejecting = true;
        return null;
    }

    // 2. Hide Input Box
    public PageReference cancelRejectMode() {
        isRejecting = false;
        rejectionReason = ''; 
        return null;
    }

    // 3. Save Reason
    public PageReference doConfirmReject() {
        if (quoteId == null) {
            hasError = true; errorMessage = 'System Error: Record ID is lost.'; return null;
        }
        if (String.isBlank(rejectionReason)) {
            hasError = true; errorMessage = 'Error: Please enter a reason for rejection.'; return null;
        }

        try {
            QuotationService.processRejection(quoteId, rejectionReason);
            rejected = true;
        } catch(Exception e) {
            hasError = true; errorMessage = e.getMessage();
        }
        return null;
    }

    // *** FIX FOR DEPLOYMENT ERROR ***
    // We keep this method here so the old Visualforce page doesn't break during saving.
    // It simply redirects to the new logic.
    public PageReference doReject() {
        return enableRejectMode();
    }
}