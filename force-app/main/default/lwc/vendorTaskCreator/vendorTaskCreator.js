import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

// Apex
import createTasks from '@salesforce/apex/TaskBulkController.createTasks';
import updateTasks from '@salesforce/apex/TaskBulkController.updateTasks';
import hasExistingTasks from '@salesforce/apex/TaskBulkController.hasExistingTasks';
import getExistingTasks from '@salesforce/apex/TaskBulkController.getExistingTasks';
import getTaskFiles from '@salesforce/apex/TaskBulkController.getTaskFiles';

import OWNER_ID_FIELD from '@salesforce/schema/Vendor_Assignment__c.OwnerId';

import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import TASK_OBJECT from '@salesforce/schema/Task';
import STATUS_FIELD from '@salesforce/schema/Task.Status';

export default class VendorTaskCreator extends LightningElement {
    @track statusOptions = [];
    
    // FIX 1: Reactive recordId to prevent "Blank Screen"
    _recordId;
    @api 
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.init(); // Auto-start whenever ID becomes available
        }
    }

    @track isLoading = true;
    @track showExistingButton = false; 
    
    showLanding = false;
    showCreation = false;
    showPreview = false;
    @track currentStep = 'start'; 

    @track taskList = []; 
    @track previewData = [];

    // Helper to view raw data if fields are still blank
    @track debugInfo = ''; 

    @wire(getRecord, { recordId: '$recordId', fields: [OWNER_ID_FIELD] })
    vendorRecord;

    get vendorOwnerId() { return getFieldValue(this.vendorRecord.data, OWNER_ID_FIELD); }

    // get statusOptions() {
    //     return [
    //         { label: 'Not Started', value: 'Not Started' },
    //         { label: 'In Progress', value: 'In Progress' },
    //         { label: 'Completed', value: 'Completed' },
    //         { label: 'Waiting on someone else', value: 'Waiting on someone else' },
    //         { label: 'Deferred', value: 'Deferred' }
    //     ];
    // }

    // ---------------- Dynamic Picklist ---------------- //

    @wire(getObjectInfo, { objectApiName: TASK_OBJECT })
    taskMetadata;

    @wire(getPicklistValues, {
        recordTypeId: '$taskMetadata.data.defaultRecordTypeId',
        fieldApiName: STATUS_FIELD
    })
    wiredStatusValues({ error, data }) {
        if (data) {
            this.statusOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            console.error('Error fetching Status picklist', error);
        }
    }

    // Initialize only when we have an ID
    async init() {
        if (!this._recordId) return;

        this.isLoading = true;
        try {
            const exists = await hasExistingTasks({ parentId: this._recordId });
            this.showExistingButton = exists;

            if (exists) {
                this.showLanding = true;
                this.showCreation = false;
                this.showPreview = false;
                this.currentStep = 'start';
            } else {
                this.showLanding = false;
                this.initCreation();
            }
        } catch (error) {
            console.error('Init Error', error);
            this.showToast('Error', 'Init failed: ' + error.body?.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    initCreation() {
        this.showLanding = false;
        this.showPreview = false;
        this.showCreation = true;
        this.currentStep = 'draft';
        if(this.taskList.length === 0) this.addNewRow();
    }

    addNewRow() {
        this.taskList.push({
            key: Date.now(),
            displayIndex: this.taskList.length + 1,
            Subject: '', Status: 'Not Started', Start_Date__c: null, ActivityDate: null, Assigned_Percentage__c: null
        });
    }

    removeRow(event) {
        if (this.taskList.length > 1) {
            this.taskList.splice(event.target.dataset.index, 1);
            this.taskList.forEach((task, idx) => { task.displayIndex = idx + 1; });
        }
    }

    get isMoreThanOneRow() { return this.taskList.length > 1; }

    handleInputChange(event) {
        this.taskList[event.target.dataset.index][event.target.dataset.field] = event.target.value;
    }

    handleCreateAndProceed() {
        // Validate inputs
        const allValid = [...this.template.querySelectorAll('lightning-input, lightning-combobox')]
            .reduce((validSoFar, inputCmp) => { inputCmp.reportValidity(); return validSoFar && inputCmp.checkValidity(); }, true);

        if (!allValid) {
            this.showToast('Error', 'Please complete all required fields', 'error');
            return;
        }

        this.isLoading = true;
        const tasksToInsert = this.taskList.map(row => ({
            sobjectType: 'Task',
            WhatId: this._recordId,
            OwnerId: this.vendorOwnerId,
            Subject: row.Subject,
            Status: row.Status,
            Start_Date__c: row.Start_Date__c,
            ActivityDate: row.ActivityDate,
            Assigned_Percentage__c: row.Assigned_Percentage__c
        }));

        createTasks({ newTasks: tasksToInsert })
            .then(() => {
                this.showToast('Success', 'Tasks created.', 'success');
                this.showExistingButton = true;
                this.taskList = [];
                this.goToPreview();
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || error.message, 'error');
                this.isLoading = false;
            });
    }

    async goToPreview() {
        this.isLoading = true;
        this.showLanding = false;
        this.showCreation = false;
        this.showPreview = true;
        this.currentStep = 'review';

        try {
            const tasks = await getExistingTasks({ parentId: this._recordId });
            
            // Debugging
            console.log('Raw Apex Data:', JSON.stringify(tasks));

            const taskIds = tasks.map(t => t.Id);
            const fileMap = await getTaskFiles({ parentIds: taskIds });

            this.previewData = tasks.map((t, index) => {
                // Normalize keys to lowercase to handle case sensitivity safely
                const flatT = {};
                Object.keys(t).forEach(key => { flatT[key.toLowerCase()] = t[key]; });

                const rawFiles = fileMap[t.Id] || [];
                const processedFileList = rawFiles.map(fd => ({
                    key: fd.documentId,
                    fileName: fd.fileName,
                    imageUrl: `/sfc/servlet.shepherd/version/download/${fd.versionId}`
                }));

                return {
                    Id: t.Id,
                    // Fixed: Switched from flatT['subject'] to flatT.subject
                    Subject: flatT.subject,
                    Status: flatT.status,
                    
                    // Fixed: Dot notation for custom fields
                    Start_Date__c: flatT.start_date__c || flatT.startdate__c,
                    ActivityDate: flatT.activitydate || flatT.duedate__c,
                    Assigned_Percentage__c: flatT.assigned_percentage__c || flatT.percentage__c,
                    
                    serialNumber: index + 1,
                    fileList: processedFileList,
                    hasFiles: processedFileList.length > 0
                };
            });

        } catch (error) {
            console.error(error);
            this.showToast('Error', 'Could not load preview', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handlePreviewChange(event) {
        const index = event.target.dataset.index;
        const field = event.target.dataset.field;
        this.previewData[index][field] = event.target.value;
    }

    handlePreviewUpload(event) {
        const files = event.detail.files;
        if (files.length > 0) {
            this.showToast('Success', 'Files uploaded.', 'success');
            this.goToPreview(); 
        }
    }

    handleFinalSave() {
        this.isLoading = true;
        const recordsToUpdate = this.previewData.map(row => ({
            Id: row.Id,
            Subject: row.Subject,
            Status: row.Status,
            Start_Date__c: row.Start_Date__c,
            ActivityDate: row.ActivityDate,
            Assigned_Percentage__c: row.Assigned_Percentage__c
        }));

        updateTasks({ tasksToUpdate: recordsToUpdate })
            .then(() => {
                this.showToast('Success', 'All records saved!', 'success');
                this.closeAction();
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || error.message, 'error');
                this.isLoading = false;
            });
    }

    closeAction() { this.dispatchEvent(new CloseActionScreenEvent()); }
    showToast(title, message, variant) { this.dispatchEvent(new ShowToastEvent({ title, message, variant })); }
}