import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCatalogConfig from '@salesforce/apex/InventoryApiService.getCatalogConfig';
import getOpportunitySummary from '@salesforce/apex/InventoryApiService.getOpportunitySummary';
import ARELIA_SITE_URL from '@salesforce/label/c.Arelia_Site_Label';


import getProducts from '@salesforce/apex/InventoryApiService.getProducts';
import saveCart from '@salesforce/apex/OpportunityQuotePDFController.saveCart';
import generateQuoteAndSave from '@salesforce/apex/OpportunityQuotePDFController.generateQuoteAndSave';
import getQualityOptions from '@salesforce/apex/QualityConfigController.getQualityOptions';
import deactivateCartItem from '@salesforce/apex/OpportunityQuotePDFController.deactivateCartItem';
import getSavedCart from '@salesforce/apex/OpportunityQuotePDFController.getSavedCart';

export default class InventoryProductManager extends LightningElement {
    @api recordId;

    /* ================= OBJECT INFO ================= */
   @track roomTypes = [];
@track categoriesByRoom = {};
    
showScrollTop = false;

@track oppSummary;

@wire(getOpportunitySummary, { opportunityId: '$recordId' })
wiredOpp({ data }) {
    if (data) {
        this.oppSummary = data;
    }
}
get isManual() {
    return this.oppSummary?.Project_Request_Quotation_Type__c === 'Manual Quotation';
}

get isAutomatic() {
    return this.oppSummary?.Project_Request_Quotation_Type__c === 'Automatic Quotation';
}

goToStep0() {
    this.currentStep = 0;
    this.updateUrlStep();
}

goToStep1() {
    this.currentStep = 1;
    this.updateUrlStep();
    this.loadCatalogConfig();
}

    /* ================= MAIN STATE ================= */
    @track _products = [];
    @track visibleProducts = [];
    @track cartItems = [];

    @track selectedRoomType = null;
    @track selectedCategory = null;

    qualityConfig = [];

    @track isLoading = false;
    @track isCartOpen = false;

    /* ================= STEP UX ================= */
    @track currentStep = 0; // 👈 START FROM STEP 0

get isStep0() { 
    return this.currentStep === 0; 
}
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }

    get stepClass1() {
    return `step ${this.currentStep === 1 ? 'active' : ''}`;
}
get stepClass2() {
    return `step ${this.currentStep === 2 ? 'active' : ''}`;
}
get stepClass3() {
    return `step ${this.currentStep === 3 ? 'active' : ''}`;
}


    /* ================= IMAGE MODAL ================= */
    @track isImageModalOpen = false;
    @track modalImageUrl = null;

    /* ================= PAGINATION ================= */
    pageSize = 8;
    currentPage = 1;
    totalPages = 1;

    /* ================= POPUP ================= */
    @track showPopup = false;
    popupTitle = '';
    popupMessage = '';

    /* ================= LIFECYCLE ================= */
    connectedCallback() {
        this.loadQualityOptions();

        // restore step from URL
        const params = new URLSearchParams(window.location.search);
        const step = Number(params.get('step'));
        if (step >= 0 && step <= 3) {
    this.currentStep = step;
}

        // ESC key closes image modal
        this._escHandler = (e) => {
            if (e.key === 'Escape' && this.isImageModalOpen) {
                this.closeImageModal();
            }
        };
        window.addEventListener('keydown', this._escHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('keydown', this._escHandler);
    }

  

get interiorProjectTypeName() {
    return this.oppSummary &&
           this.oppSummary.Interior_Project_Type__r
        ? this.oppSummary.Interior_Project_Type__r.Name
        : '';
}

get backButtonLabel() {
    return this.currentStep === 1 ? 'Back to Summary' : 'Back';
}

handleBackClick() {
    if (this.currentStep === 1) {
        this.goToStep0();   // Step 1 → Summary
    } else {
        this.goBack();     // Step 2/3 → previous step
    }
}
    /* ================= URL STEP ================= */
    updateUrlStep() {
        const url = new URL(window.location.href);
        url.searchParams.set('step', this.currentStep);
        window.history.replaceState({}, '', url.toString());
    }

    goBack() {
    if (this.currentStep > 0) {
        this.currentStep--;
        this.updateUrlStep();
    }
}
    loadCatalogConfig() {
    if (!this.recordId) return;

    getCatalogConfig({ opportunityId: this.recordId })
        .then(res => {
            this.roomTypes = res.rooms || [];
            this.categoriesByRoom = res.categoriesByRoom || {};
            if (!this.roomTypes.length) {
        this.showToast(
            'No Products Available',
            'No catalogue items found for this project type',
            'warning'
        );
    }
        })
        .catch(() => {
            this.showToast(
                'Error',
                'Unable to load catalogue configuration',
                'error'
            );
        });
}


    /* ================= COMMUNITY PARAM ================= */
    @wire(CurrentPageReference)
getPageRef(pageRef) {
    if (pageRef?.state?.id) {
        this.recordId = pageRef.state.id;

       
        this.fetchSavedCart();
    }
}

    

    /* ================= UI GETTERS ================= */
    get roomTypesUI() {
    return this.roomTypes.map(v => ({
        value: v,
        className: `chip ${this.selectedRoomType === v ? 'chip-selected' : ''}`
    }));
}

    get categories() {
    const cats = this.categoriesByRoom[this.selectedRoomType] || [];
    return cats.map(v => ({
        value: v,
        className: `chip ${this.selectedCategory === v ? 'chip-selected' : ''}`
    }));
}

    get selectedProductsList() {
        return this.cartItems.map(i => ({
            id: i.Interior_Product__c,
            name: i.Name,
            qty: i.Quantity__c,
            quality: i.Quality__c,
            Room_Type__c: i.Room_Type__c,
            Product_Category__c: i.Product_Category__c
        }));
    }

    /* ================= STEP HANDLERS ================= */
    handleRoomSelect(event) {
    this.selectedRoomType = event.currentTarget.dataset.value;
    this.selectedCategory = null;

    // 🔥 Reset dependent state
    this.products = [];
    this.visibleProducts = [];
    this.currentPage = 1;

    this.currentStep = 2;
    this.updateUrlStep();
}

    handleCategorySelect(event) {
        this.selectedCategory = event.currentTarget.dataset.value;
        this.currentStep = 3;
        this.updateUrlStep();
        this.loadProducts();
    }

    /* ================= PRODUCT CLICK (FROM CART) ================= */
    handleSelectedProductClick(event) {
    // 🔥 HARD BLOCK: ignore delete clicks
    if (event.target.closest('.remove-btn')) {
        return;
    }

    this.isCartOpen = false;

    const productId = event.currentTarget.dataset.id;
    const selectedItem = this.cartItems.find(
        i => i.Interior_Product__c === productId
    );
    if (!selectedItem) return;

    this.selectedRoomType = selectedItem.Room_Type__c;
    this.selectedCategory = selectedItem.Product_Category__c;
    this.currentStep = 3;
    this.updateUrlStep();

    this.loadProducts();

    setTimeout(() => {
        const idx = this._products.findIndex(p => p.Id === productId);
        if (idx < 0) return;

        this.currentPage = Math.floor(idx / this.pageSize) + 1;
        this.calculatePagination();

        setTimeout(() => {
            const card = this.template.querySelector(
                `[data-product="${productId}"]`
            );
            if (card) {
                card.scrollIntoView({ behavior: 'smooth', block: 'center' });
                card.classList.add('highlight-product');
                setTimeout(
                    () => card.classList.remove('highlight-product'),
                    2000
                );
            }
        }, 100);
    }, 300);
}

    syncProductsWithCart() {
    if (!this.products?.length || !this.cartItems?.length) return;

    this.products = this.products.map(p => {
        const item = this.cartItems.find(
            c => c.Interior_Product__c === p.Id
        );

        return item
            ? {
                ...p,
                qty: item.Quantity__c,
                inCart: true,
                selectedQuality: item.Quality__c,
                displayPrice: item.Unit_Price__c,
                isStandard: item.Quality__c === 'Standard',
                isPremium: item.Quality__c === 'Premium',
                isLuxury: item.Quality__c === 'Luxury'
              }
            : {
                ...p,
                qty: 0,
                inCart: false,
                selectedQuality: 'Standard',
                displayPrice: p.Unit_Price__c,
                isStandard: true,
                isPremium: false,
                isLuxury: false
              };
    });
}


    /* ================= LOAD PRODUCTS ================= */
    loadProducts() {
        if (!this.selectedRoomType || !this.selectedCategory) return;

        this.isLoading = true;

        getProducts({
            roomType: this.selectedRoomType,
            category: this.selectedCategory
        })
            .then(res => {
                this.products = (res || []).map(p => {
                    const cartItem = this.cartItems.find(c => c.Interior_Product__c === p.Id);
                    const quality = cartItem?.Quality__c || 'Standard';
                    const price = cartItem?.Unit_Price__c || p.Unit_Price__c;

                    return {
                        ...p,
                        qty: cartItem?.Quantity__c || 0,
                        inCart: !!cartItem,
                        selectedQuality: quality,
                        displayPrice: price,
                        isStandard: quality === 'Standard',
                        isPremium: quality === 'Premium',
                        isLuxury: quality === 'Luxury',
                        imageUrl: this.buildImageUrl(p),
                        qualityGroupName: `quality-${p.Id}`,
                        standardId: `standard-${p.Id}`,
                        premiumId: `premium-${p.Id}`,
                        luxuryId: `luxury-${p.Id}`
                    };
                });
                this.syncProductsWithCart();
            })
            .catch(() => this.showToast('Error', 'Failed to load products', 'error'))
            .finally(() => (this.isLoading = false));
    }

    /* ================= QUALITY ================= */
    loadQualityOptions() {
        getQualityOptions().then(res => (this.qualityConfig = res || []));
    }

    handleQualityRadio(event) {
        const productId = event.currentTarget.dataset.id;
        const selectedQuality = event.target.value;

        const prod = this.products.find(p => p.Id === productId);
        if (!prod) return;

        const cfg = this.qualityConfig.find(q => q.Quality__c === selectedQuality);
        const multiplier = cfg ? cfg.Multiplier__c : 1;
        const newPrice = Math.round(prod.Unit_Price__c * multiplier);

        this.products = this.products.map(p =>
            p.Id === productId
                ? {
                      ...p,
                      selectedQuality,
                      displayPrice: newPrice,
                      isStandard: selectedQuality === 'Standard',
                      isPremium: selectedQuality === 'Premium',
                      isLuxury: selectedQuality === 'Luxury'
                  }
                : p
        );
    }

    /* ================= PAGINATION ================= */
    set products(value) {
        this._products = value || [];
        this.currentPage = 1;
        this.calculatePagination();
    }

    get products() {
        return this._products;
    }

    calculatePagination() {
        this.totalPages = Math.max(1, Math.ceil(this._products.length / this.pageSize));
        const start = (this.currentPage - 1) * this.pageSize;
        this.visibleProducts = this._products.slice(start, start + this.pageSize);
    }

    get isFirstPage() { return this.currentPage === 1; }
    get isLastPage() { return this.currentPage === this.totalPages; }

    nextPage() {
        if (!this.isLastPage) {
            this.currentPage++;
            this.calculatePagination();
        }
    }

    prevPage() {
        if (!this.isFirstPage) {
            this.currentPage--;
            this.calculatePagination();
        }
    }

    /* ================= CART ================= */
    get cartTotal() {
        return this.cartItems.reduce((s, i) => s + (i.Total_Amount__c || 0), 0);
    }

    get cartLabel() {
        return `Cart (${this.cartItems.length})`;
    }

    handleAddToCart(event) {
        const productId = event.currentTarget.dataset.id;
        const prod = this.products.find(p => p.Id === productId);
        if (!prod) return;
        this.updateQty(productId, 1, prod.displayPrice, prod.selectedQuality);
    }

    handleQtyPlus(event) {
        const productId = event.currentTarget.dataset.id;
        const prod = this.products.find(p => p.Id === productId);
        this.updateQty(productId, prod.qty + 1, prod.displayPrice, prod.selectedQuality);
    }

    handleQtyMinus(event) {
        const productId = event.currentTarget.dataset.id;
        const prod = this.products.find(p => p.Id === productId);
        this.updateQty(productId, Math.max(prod.qty - 1, 0), prod.displayPrice, prod.selectedQuality);
    }

    updateQty(productId, qty, price, quality) {
        const prod = this.products.find(p => p.Id === productId);
        let cart = [...this.cartItems];
        const idx = cart.findIndex(c => c.Interior_Product__c === productId);

        if (qty > 0) {
            if (idx >= 0) {
                cart[idx] = {
                    ...cart[idx],
                    Name: prod ? prod.Name : cart[idx].Name,
                    Quantity__c: qty,
                    Unit_Price__c: price,
                    Quality__c: quality,
                    Total_Amount__c: qty * price
                };
            } else {
                cart.push({
                    sobjectType: 'Project_Specification__c',
                    Opportunity__c: this.recordId,
                    Interior_Product__c: productId,
                    Name: prod?.Name,

                      // 🔥 ADD THESE TWO
    Room_Type__c: this.selectedRoomType || prod?.Room_Type__c || 'Unknown',
Product_Category__c: this.selectedCategory || prod?.Product_Category__c || 'Others',
                    Quantity__c: qty,
                    Unit_Price__c: price,
                    Quality__c: quality,
                    Total_Amount__c: qty * price
                });
            }
        } else {
            cart = cart.filter(c => c.Interior_Product__c !== productId);
        }

        this.cartItems = cart;

        this.products = this.products.map(p => {
            const item = cart.find(c => c.Interior_Product__c === p.Id);
            return item
                ? {
                      ...p,
                      qty: item.Quantity__c,
                      inCart: true,
                      selectedQuality: item.Quality__c,
                      displayPrice: item.Unit_Price__c,
                      isStandard: item.Quality__c === 'Standard',
                      isPremium: item.Quality__c === 'Premium',
                      isLuxury: item.Quality__c === 'Luxury'
                  }
                : {
                      ...p,
                      qty: 0,
                      inCart: false,
                      selectedQuality: 'Standard',
                      displayPrice: p.Unit_Price__c,
                      isStandard: true,
                      isPremium: false,
                      isLuxury: false
                  };
        });
    }
    handleQtyInput(event) {
    const productId = event.currentTarget.dataset.id;
    let qty = parseInt(event.target.value, 10);

    if (isNaN(qty) || qty < 0) qty = 0;

    const prod = this.products.find(p => p.Id === productId);
    if (!prod) return;

    this.updateQty(productId, qty, prod.displayPrice, prod.selectedQuality);
}

    /* ================= CART MODAL ================= */
    openCart() {
        this.isCartOpen = true;
    }

    closeCart() {
        this.isCartOpen = false;
    }

    handleClearCart() {
        this.cartItems = [];
        this.products = this.products.map(p => ({
            ...p,
            qty: 0,
            inCart: false,
            selectedQuality: 'Standard',
            displayPrice: p.Unit_Price__c,
            isStandard: true,
            isPremium: false,
            isLuxury: false
        }));
        this.closeCart();
        this.showToast('Cleared', 'Cart cleared successfully', 'success');
    }

    handleRemoveItem(event) {
    const specId = event.currentTarget.dataset.id;
    const productId = event.currentTarget.dataset.productid;

    // 🔥 CASE 1: UNSAVED ITEM (no Id yet)
    if (!specId) {
        this.cartItems = this.cartItems.filter(
            i => i.Interior_Product__c !== productId
        );

        this.syncProductsWithCart();
        this.showToast('Removed', 'Item removed from cart', 'success');
        return;
    }

    // 🔥 CASE 2: SAVED ITEM (has Id)
    const removedItem = this.cartItems.find(i => i.Id === specId);

    this.cartItems = this.cartItems.filter(i => i.Id !== specId);
    this.syncProductsWithCart();
    this.isLoading = true;

    deactivateCartItem({ specItemId: specId })
        .then(() => {
            this.showToast('Removed', 'Item removed from cart', 'success');
        })
        .catch(error => {
            // rollback if Apex fails
            if (removedItem) {
                this.cartItems = [...this.cartItems, removedItem];
                this.syncProductsWithCart();
            }

            this.showToast(
                'Error',
                error?.body?.message || 'Could not remove item',
                'error'
            );
        })
        .finally(() => {
            this.isLoading = false;
        });
}
handleCartScroll(event) {
    const shouldShow = event.target.scrollTop > 150;
    if (shouldShow !== this.showScrollTop) {
        this.showScrollTop = shouldShow;
    }
}

scrollCartToTop() {
    const el = this.template.querySelector('.cart-body');
    el?.scrollTo({ top: 0, behavior: 'smooth' });
}

    /* ================= GENERATE QUOTE ================= */
    handleGenerateClick() {
        if (!this.cartItems.length) {
            this.showCustomPopup('⚠️ Cart Empty', 'Add items before generating quotation.');
            return;
        }

        this.isLoading = true;

        const cleanedCart = this.cartItems.map(item => {
            const clone = { ...item };
            delete clone.Id;
            return clone;
        });

        saveCart({ opportunityId: this.recordId, cartItems: cleanedCart })
            .then(() => generateQuoteAndSave({ opportunityId: this.recordId }))
            .then(() => {
                this.isLoading = false;
                this.showCustomPopup('🎉 Success', 'Quotation PDF generated & emailed!');
            })
            .catch(error => {
    this.isLoading = false;
    const msg =
        error?.body?.message ||
        error?.message ||
        'PDF generation failed. Check product data.';
    this.showToast('Error', msg, 'error');
});
    }

    /* ================= IMAGE MODAL ================= */
    openImageModal(event) {
        this.modalImageUrl = event.currentTarget.dataset.url;
        this.isImageModalOpen = true;
    }

    closeImageModal() {
        this.isImageModalOpen = false;
        this.modalImageUrl = null;
    }

    stopEvent(event) {
        event.stopPropagation();
    }

    /* ================= POPUP ================= */
    showCustomPopup(title, message) {
        this.popupTitle = title;
        this.popupMessage = message;
        this.showPopup = true;
    }

    closePopup() {
    this.showPopup = false;

    setTimeout(() => {
        window.location.href = ARELIA_SITE_URL;
    }, 300);
}


    /* ================= HELPERS ================= */
    fetchSavedCart() {
    if (!this.recordId) return;

    getSavedCart({ opportunityId: this.recordId })
        .then(items => {
            this.cartItems = items || [];

            // 🔥 ADD THIS
            if (this.currentStep === 3) {
                this.syncProductsWithCart();
            }
        });
}

    buildImageUrl(product) {
        return product?.Image_File_Name__c
            ? `/resource/${product.Image_File_Name__c}`
            : '/resource/Default_Product_Image';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant, mode: 'dismissible' })
        );
    }
}