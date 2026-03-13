import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getBudgetReview from '@salesforce/apex/OpportunityBudgetReviewController.getBudgetReview';
import submitDecision from '@salesforce/apex/OpportunityBudgetReviewController.submitDecision';
import ARELIA_SITE_LABEL from '@salesforce/label/c.Arelia_Site_Label'; 
import LightningAlert from 'lightning/alert';
import LightningConfirm from 'lightning/confirm';

export default class BudgetReviewApproval extends LightningElement {
    @track approvalData;
    @track comments = '';
    @track isLoading = true;
    @track error;
    @track showCommentBox = false;
    @track isProcessed = false;
    @track showSuccessModal = false;
    
    recordId;
    userType; 
    currentStatus;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            let id = currentPageReference.state.id;
            let type = currentPageReference.state.type;

            if (!id || !type) {
                const urlParams = new URLSearchParams(window.location.search);
                if (!id) id = urlParams.get('id');
                if (!type) type = urlParams.get('type');
            }

            this.recordId = id;
            this.userType = type || 'Manager'; 

            if (this.recordId) {
                this.loadData();
            } else {
                this.error = 'Invalid Link: Record ID missing.';
                this.isLoading = false;
            }
        }
    }

    loadData() {
        getBudgetReview({ opportunityId: this.recordId })
            .then(result => {
                this.approvalData = result;
                this.isLoading = false;
                this.currentStatus = result.opportunity.Budget_Review_Status__c;
                
                const s = this.currentStatus;
                
                // --- STATUS LOCKING LOGIC ---
                this.isProcessed = true; // Default to locked

                if (this.userType === 'Client') {
                    // Client acts FIRST.
                    // Active only if status is "Sent for Client Approval"
                    if (s === 'Sent for Client Approval') {
                        this.isProcessed = false;
                    }
                } else { 
                    // Manager acts LAST (Second).
                    // Active only if "Client Approved" (or if Manager requested changes previously)
                    if (s === 'Client Approved' || s === 'Manager Requested Changes') {
                        this.isProcessed = false;
                    }
                }
            })
            .catch(err => {
                console.error(err);
                this.error = 'Error loading data.';
                this.isLoading = false;
            });
    }

    get isClient() { return this.userType === 'Client'; }
    get isRevised() { return this.approvalData && this.approvalData.opportunity.Budget_Review_Client_Remarks__c; }
    
    // Dynamic Label based on Role
    get approveButtonLabel() { 
        return this.isClient ? 'Approve' : 'Final Approve'; 
    }
    
    get clientName() {
        return (this.approvalData && this.approvalData.opportunity.Primary_Contact__r) 
            ? this.approvalData.opportunity.Primary_Contact__r.Name 
            : 'Valued Client';
    }

    get supervisorName() {
        if (this.approvalData && this.approvalData.opportunity.Supervisor_User__r) {
            const f = this.approvalData.opportunity.Supervisor_User__r.FirstName || '';
            const l = this.approvalData.opportunity.Supervisor_User__r.LastName || '';
            return `${f} ${l}`;
        }
        return 'Supervisor';
    }

    get supervisorEmail() {
        return (this.approvalData && this.approvalData.opportunity.Supervisor_User__r)
            ? this.approvalData.opportunity.Supervisor_User__r.Email
            : '';
    }

    handleCommentChange(e) { this.comments = e.target.value; }

    async handleApproveClick() {
        this.comments = '';
        this.showCommentBox = false;

        const msg = this.isClient 
            ? 'Are you sure you want to APPROVE this budget? This will send it to the Manager.'
            : 'Are you sure you want to provide FINAL APPROVAL? This will lock the budget.';
        
        const result = await LightningConfirm.open({
            message: msg,
            variant: 'header',
            label: 'Confirm Approval',
            theme: 'success',
        });
        if (result) this.submit('Approve');
    }

    handleRequestChangesClick() { this.showCommentBox = !this.showCommentBox; }

    async handleRejectClick() {
        if (!this.comments || this.comments.trim() === '') {
            await LightningAlert.open({
                message: 'Please enter remarks.',
                theme: 'error',
                label: 'Validation Error',
            });
            return;
        }
        const result = await LightningConfirm.open({
            message: 'Are you sure you want to request changes?',
            variant: 'header',
            label: 'Confirm Request',
            theme: 'warning',
        });
        if (result) this.submit('Reject');
    }

    submit(action) {
        this.isLoading = true;
        const decisionData = {
            userType: this.userType,
            action: action,
            comments: this.comments
        };

        submitDecision({ recordId: this.recordId, data: decisionData })
        .then(() => {
            this.isLoading = false;
            this.showSuccessModal = true; 
        })
        .catch(err => {
            this.isLoading = false;
            this.error = err.body ? err.body.message : err.message;
        });
    }

    handleNavigateHome() {
        window.location.href = ARELIA_SITE_LABEL;
    }
}