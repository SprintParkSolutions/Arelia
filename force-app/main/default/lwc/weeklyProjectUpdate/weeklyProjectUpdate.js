import { LightningElement, wire, track } from 'lwc';
import getSupervisorProjects from '@salesforce/apex/WeeklyProjectUpdateController.getSupervisorProjects';
import sendWeeklyEmail from '@salesforce/apex/WeeklyProjectUpdateController.sendWeeklyEmail';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class WeeklyProjectUpdate extends LightningElement {

    @track projects = [];
    showProjectList = true;
    showUpdatePanel = false;

    selectedProjectId;
    selectedProjectName;
    weekNumber;
    message = '';
   
    @track uploadedFiles = [];      // for UI display
uploadedFileIds = []; 

    acceptedFormats = ['.pdf', '.jpg', '.jpeg', '.png', '.mp4', '.mov'];

    @wire(getSupervisorProjects)
    wiredProjects({ data, error }) {
        if (data) {
            this.projects = data.map(p => ({
                ...p,
                ClientName: p.Client__r ? p.Client__r.Name : ''
            }));
        } else if (error) {
            console.error(error);
        }
    }

    handleProjectSelect(event) {
    this.selectedProjectId = event.currentTarget.dataset.id;
    const proj = this.projects.find(p => p.Id === this.selectedProjectId);
    this.selectedProjectName = proj.Name;

    this.weekNumber = this.calculateWeek(proj.Start_Date__c);

    // RESET FILE STATE
    this.uploadedFiles = [];
    this.uploadedFileIds = [];
    this.message = '';

    this.showProjectList = false;
    this.showUpdatePanel = true;
}

    calculateWeek(startDate) {
        if (!startDate) return 1;
        const start = new Date(startDate);
        const today = new Date();
        const diffDays = Math.floor((today - start) / (1000 * 60 * 60 * 24));
        return Math.floor(diffDays / 7) + 1;
    }

    handleMessage(event) {
        this.message = event.target.value;
    }

    handleUpload(event) {
    const uploaded = event.detail.files;

    uploaded.forEach(file => {
        // UI list
        this.uploadedFiles = [
            ...this.uploadedFiles,
            {
                name: file.name,
                documentId: file.documentId
            }
        ];

        // IDs for Apex
        this.uploadedFileIds.push(file.documentId);
    });
}

    goBack() {
        this.showProjectList = true;
        this.showUpdatePanel = false;
        this.message = '';
        this.uploadedFileIds = [];
    }

    sendUpdate() {
        sendWeeklyEmail({
    projectId: this.selectedProjectId,
    weeklySummary: this.message,   
    fileIds: this.uploadedFileIds
})
        .then(() => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Weekly update sent successfully',
                    variant: 'success'
                })
            );
            
            this.uploadedFiles = [];
    this.uploadedFileIds = [];
    this.message = '';
    this.goBack();
        })
        .catch(error => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body ? error.body.message : error.message,
                    variant: 'error'
                })
            );
        });
    }
}