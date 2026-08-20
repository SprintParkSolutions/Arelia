import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

import estimateVendorsFromOpportunity from '@salesforce/apex/VendorEstimationService.estimateVendorsFromOpportunity';
import estimateTasksForVendor from '@salesforce/apex/VendorEstimationService.estimateTasksForVendor';
import estimateFromImages from '@salesforce/apex/VendorEstimationService.estimateFromImages';
import generateProforma from '@salesforce/apex/VendorEstimationService.generateProforma';
import generateProformaFromImages from '@salesforce/apex/VendorEstimationService.generateProformaFromImages'; // ✅ FIX


export default class OpportunityVendorEstimator extends LightningElement {

    @track currentScreen = 'intro';
    @track estimates = [];
    @track taskEstimates = [];
    @track selectedVendor;
    @track isLoading = false;
    @track errorMessage;

    @track uploadedFileIds = [];
    @track uploadedImages = [];

    @track showProforma = false;
    @track proformaData;

    totalBudget = 0;
    usableBudget = 0;

    @api recordId;
    effectiveRecordId;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef){
        this.effectiveRecordId =
            this.recordId ||
            pageRef?.state?.recordId ||
            pageRef?.state?.id;
    }

    // =========================
    // 🔹 NORMAL ESTIMATION
    // =========================
    async handleEstimate(){

        if(!this.effectiveRecordId){
            this.errorMessage = 'Opportunity record not found';
            return;
        }

        try{
            this.isLoading = true;
            this.errorMessage = null;

            const result = await estimateVendorsFromOpportunity({
                opportunityId: this.effectiveRecordId
            });

            if(!result || result.length === 0){
                this.errorMessage = 'No data returned from AI';
                return;
            }

            this.prepareVendorData(result);
            this.currentScreen = 'vendors';

        }catch(error){
            console.error('ERROR:', error);
            this.errorMessage = 'AI estimation failed. Please try again.';
        }
        finally{
            this.isLoading = false;
        }
    }

    // =========================
    // 🔹 UPLOAD
    // =========================
    openUpload(){
        this.currentScreen = 'upload';
    }

    handleUploadFinished(event){

        event.detail.files.forEach(file => {
            this.uploadedFileIds.push(file.documentId);

            this.uploadedImages.push({
                id: file.documentId,
                name: file.name,
                url: '/sfc/servlet.shepherd/document/download/' + file.documentId
            });
        });
    }

    // =========================
    // 🔹 IMAGE ESTIMATION
    // =========================
    async handleImageEstimate(){

        if(this.uploadedFileIds.length === 0){
            this.errorMessage = 'Upload at least one image';
            return;
        }

        try{
            this.isLoading = true;
            this.errorMessage = null;

            const result = await estimateFromImages({
                contentDocumentIds: this.uploadedFileIds
            });

            this.prepareVendorData(result);

            this.currentScreen = 'vendors';

        }catch(error){
            console.error(error);
            this.errorMessage = 'Multi-image AI estimation failed';
        }
        finally{
            this.isLoading = false;
        }
    }

    // =========================
    // 🔹 PREP DATA
    // =========================
    prepareVendorData(result){

        if(!result || result.length === 0){
            this.errorMessage = 'No data returned from AI';
            return;
        }

        this.totalBudget = result[0].totalBudget || 0;
        this.usableBudget = result[0].usableBudget || 0;

        this.estimates = result.map(item => ({
            ...item,
            estimatedAmountFormatted: this.formatCurrency(item.estimatedAmount),
            progressStyle: `width:${item.percentage}%`
        }));
    }

    // =========================
    // 🔹 TASKS
    // =========================
    async handleVendorClick(event){

        try{
            const category = event.currentTarget.dataset.category;
            const budget = parseFloat(event.currentTarget.dataset.budget);

            this.selectedVendor = category;
            this.isLoading = true;

            const result = await estimateTasksForVendor({
                vendorCategory: category,
                vendorBudget: budget
            });

            this.taskEstimates = result.map(t => ({
                ...t,
                amountFormatted: this.formatCurrency(t.estimatedAmount),
                style: `width:${t.percentage}%`
            }));

            this.currentScreen = 'tasks';

        }catch(error){
            console.error(error);
            this.errorMessage = 'Task estimation failed';
        }
        finally{
            this.isLoading = false;
        }
    }

    // =========================
    // 🔹 Generate Proforma
    // =========================

    async handleGenerateProforma(){

        try{
            this.isLoading = true;
            this.errorMessage = null;

            let result;

            // 🔥 Smart logic
            if(this.uploadedFileIds && this.uploadedFileIds.length > 0){

                result = await generateProformaFromImages({
                    contentDocumentIds: this.uploadedFileIds,
                    vendors: this.estimates
                });

            }else{

                result = await generateProforma({
                    vendors: this.estimates
                });
            }

            console.log('PROFORMA RESULT:', JSON.stringify(result));

            if(!result || !result.sections){
                this.errorMessage = 'AI returned invalid proforma';
                return;
            }

            this.proformaData = result;
            this.showProforma = true;

        }catch(e){
            console.error('PROFORMA ERROR:', e);
            this.errorMessage = 'Proforma generation failed';
        }finally{
            this.isLoading = false;
        }
    }

    handleClose(){
        this.currentScreen = 'intro';
    }

    handleCloseTasks(){
        this.currentScreen = 'vendors';
    }

    formatCurrency(val){
        return new Intl.NumberFormat('en-IN',{
            style:'currency',
            currency:'INR'
        }).format(val || 0);
    }

    get formattedTotalBudget(){
        return this.formatCurrency(this.totalBudget);
    }

    get formattedUsableBudget(){
        return this.formatCurrency(this.usableBudget);
    }

    get isIntro(){ return this.currentScreen === 'intro'; }
    get isUpload(){ return this.currentScreen === 'upload'; }
    get isVendors(){ return this.currentScreen === 'vendors'; }
    get isTasks(){ return this.currentScreen === 'tasks'; }


   // =========================
// 🔥 COMMON SCROLL HELPER
// =========================
scrollContainer(containerSelector, direction){

    const container = this.template.querySelector(containerSelector);
    if(!container) return;

    const card = container.querySelector('.premium-card, .premium-task');
    const cardWidth = card ? card.offsetWidth + 24 : 360;

    container.scrollBy({
        left: direction * cardWidth,
        behavior: 'smooth'
    });

    // Update arrow visibility after scroll
    setTimeout(()=>{
        this.updateArrows(containerSelector);
    }, 400);
}


// =========================
// 🔥 VENDOR SCROLL
// =========================
scrollVendorLeft(){
    this.scrollContainer('[data-id="vendorScroll"]', -1);
}

scrollVendorRight(){
    this.scrollContainer('[data-id="vendorScroll"]', 1);
}


// =========================
// 🔥 TASK SCROLL
// =========================
scrollLeft(){
    this.scrollContainer('[data-id="taskScroll"]', -1);
}

scrollRight(){
    this.scrollContainer('[data-id="taskScroll"]', 1);
}


// =========================
// 🔥 AUTO ARROW VISIBILITY
// =========================
updateArrows(selector){

    const container = this.template.querySelector(selector);
    if(!container) return;

    const leftArrow = this.template.querySelector(selector.includes('vendor')
        ? '.vendor-left'
        : '.task-left');

    const rightArrow = this.template.querySelector(selector.includes('vendor')
        ? '.vendor-right'
        : '.task-right');

    if(!leftArrow || !rightArrow) return;

    const scrollLeft = container.scrollLeft;
    const maxScroll = container.scrollWidth - container.clientWidth;

    leftArrow.style.opacity = scrollLeft <= 10 ? '0.3' : '1';
    rightArrow.style.opacity = scrollLeft >= maxScroll - 10 ? '0.3' : '1';
}


// =========================
// 🔥 INIT AFTER RENDER
// =========================
renderedCallback(){

    this.initScroll('[data-id="vendorScroll"]');
    this.initScroll('[data-id="taskScroll"]');
}


// =========================
// 🔥 SCROLL INIT + SWIPE
// =========================
initScroll(selector){

    const container = this.template.querySelector(selector);
    if(!container || container.dataset.init) return;

    container.dataset.init = true;

    this.updateArrows(selector);

    // Scroll listener (for arrow auto update)
    container.addEventListener('scroll', ()=>{
        this.updateArrows(selector);
    });

    // 🔥 TOUCH / DRAG SUPPORT
    let isDown = false;
    let startX;
    let scrollLeft;

    container.addEventListener('mousedown', (e)=>{
        isDown = true;
        container.classList.add('dragging');
        startX = e.pageX - container.offsetLeft;
        scrollLeft = container.scrollLeft;
    });

    container.addEventListener('mouseleave', ()=> isDown = false);
    container.addEventListener('mouseup', ()=> isDown = false);

    container.addEventListener('mousemove', (e)=>{
        if(!isDown) return;
        e.preventDefault();
        const x = e.pageX - container.offsetLeft;
        const walk = (x - startX) * 1.5;
        container.scrollLeft = scrollLeft - walk;
    });
}
}