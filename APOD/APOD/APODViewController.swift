//
//  APODViewController.swift
//  APOD
//
//  Created by user220349 on 5/29/22.
//

import Foundation
import UIKit

class APODViewController: UIViewController, PODDelegate, DJKFlipperDataSource {
    @IBOutlet weak var dateButton: UIButton?
    @IBOutlet weak var titleLabel: UILabel?
    @IBOutlet weak var descriptionLabel: UITextView?
    @IBOutlet weak var assetView: APODAssetView?
    @IBOutlet weak var favoriteButton: UIButton?
    @IBOutlet weak var moreButton: UIButton?
    @IBOutlet weak var datePicker: UIDatePicker?
    @IBOutlet weak var flipView: DJKFlipperView?
    
    @IBOutlet weak var assetViewHeightConstant: NSLayoutConstraint?
    
    private var prevViewController: APODViewController?
    private var currentViewController: APODViewController?
    private var nextViewController: APODViewController?
    
    private let dataController = APODDataController()
    
    
    private var flipperViewArray: [UIViewController]?
    {
        didSet
        {
            self.flipView?.reload()
            
        }
    }
    
    
    init() {
        super.init(nibName: nil, bundle: nil)
        self.dataController.podDelegate = self
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.dataController.podDelegate = self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        datePicker?.maximumDate = Date()
        flipView?.dataSource = self
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.setupAssetViewHeightConstant()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.setupAssetViewHeightConstant()
    }
    
    func setupAssetViewHeightConstant() {
        guard let flipView = flipView, let cvc = currentViewController else {
            return
        }
        let heightConstant = (self.view.frame.height - flipView.frame.height) * 0.6
        prevViewController?.assetViewHeightConstant?.constant = heightConstant
        cvc.assetViewHeightConstant?.constant = heightConstant
        nextViewController?.assetViewHeightConstant?.constant = heightConstant
    }
    
    // remove this
    @IBAction func clearPersistentStore() {
        self.dataController.clearPersistentStore()
    }
    
    @IBAction func dateSelected() {
        // show date picker for custom date selection
        guard let datePickerView = datePicker?.superview?.superview else {
            return
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        datePickerView.isHidden = !datePickerView.isHidden
        if datePickerView.isHidden, let date = datePicker?.date {
            let dateStr = dateFormatter.string(from: date)
            dateButton?.setTitle(dateStr, for: .normal)
            dataController.date = dateStr
        } else if let dateStr = dateButton?.title(for: .normal), let date = dateFormatter.date(from: dateStr) {
            datePicker?.date = date
        }
    }
    
    @IBAction func markFavorite() {
        self.dataController.markFavorite()
    }
    
    @IBAction func showMore() {
        guard let csh = descriptionLabel?.contentSize.height, let vsh = descriptionLabel?.visibleSize.height, let co = descriptionLabel?.contentOffset else { return }
        var newY = min(co.y + vsh - 20.0, csh - vsh)
        if Int(newY) == Int(co.y) { newY = 0 }
        UIView.animate(withDuration: 0.5, animations: { [weak self] in
            self?.descriptionLabel?.contentOffset = CGPoint(x: co.x, y: newY)
        })
    }
    
    // pod delegate implementation
    
    func fetchedPicOfDayDetails(_ details: [String: Any?]?) {
        guard let details = details else {
            dateButton?.isEnabled = false
            titleLabel?.text = ""
            descriptionLabel?.text = ""
            assetView?.loadResource(type: .none, url: nil)
            favoriteButton?.isEnabled = false
            descriptionLabel?.contentOffset = CGPoint.zero
            moreButton?.isHidden = true
            return
        }
        dateButton?.isEnabled = true
        dateButton?.setTitle(details["date"] as? String, for: .normal)
        titleLabel?.text = details["title"] as? String
        descriptionLabel?.text = details["explanation"] as? String
        favoriteButton?.isEnabled = true
        if descriptionLabel?.contentSize.height ?? 0 > descriptionLabel?.visibleSize.height ?? 0 {
            moreButton?.isHidden = false
        }
        if let favorite = details["favorite"] as? Bool, favorite == true {
            favoriteButton?.setImage(UIImage(systemName: "heart.fill"), for: .normal)
        } else {
            favoriteButton?.setImage(UIImage(systemName: "heart"), for: .normal)
        }
        
        if (details["media_type"] as? String) == "video" {
            assetView?.loadResource(type: .image, url: ImageURLProtocol.fileURL(with: details["thumbnail_url"] as? String))
            // Do not load video for preview viewcontroller i.e with no flipView
            guard let _ = flipView, let videoUrl = details["url"] as? String else  { return }
            assetView?.loadResource(type: .video, url: URL(string: videoUrl))
        } else {
            assetView?.loadResource(type: .image, url: ImageURLProtocol.fileURL(with: details["url"] as? String))
        }
        
        // manage flipviewControllers
        manageFlipViewControllers()
        
    }
    
    func dateByAdding(dayCount: Int, to date: Date) -> String {
        let calendar = Calendar.current
        guard let ndate = calendar.date(byAdding: .day, value: dayCount, to: date) else { return "" }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: ndate)
    }
    
    func configure(for dateStr: String) {
        dateButton?.setTitle(dateStr, for: .normal)
        dataController.date = dateStr
    }
    
    func manageFlipViewControllers() {
        guard let flipView = flipView else { return }
        if prevViewController == nil, nextViewController == nil, currentViewController == nil {
            flipView.dataSource = self
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            prevViewController = storyboard.instantiateViewController(withIdentifier: "FlipSnapshot") as? APODViewController
            prevViewController?.view.frame = flipView.bounds
            currentViewController = storyboard.instantiateViewController(withIdentifier: "FlipSnapshot") as? APODViewController
            currentViewController?.view.frame = flipView.bounds
            nextViewController = storyboard.instantiateViewController(withIdentifier: "FlipSnapshot") as? APODViewController
            nextViewController?.view.frame = flipView.bounds
            setupAssetViewHeightConstant()
        }
        guard let pvc = prevViewController, let nvc = nextViewController, let cvc = currentViewController else { return }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let dateStr = dateButton?.title(for: .normal), let date = dateFormatter.date(from: dateStr) else {
           return
        }
        
        cvc.configure(for: dateStr)
        
        // current view is showing pic details of today
        if let maxDate = datePicker?.maximumDate, dateFormatter.string(from: maxDate) == dateStr {
            pvc.configure(for: dateByAdding(dayCount: -1, to: maxDate))
            flipView.currentPage = 1
            flipperViewArray = [pvc, cvc]
        } else if let minDate = datePicker?.minimumDate, dateFormatter.string(from: minDate) == dateStr {
            nvc.configure(for: dateByAdding(dayCount: 1, to: minDate))
            flipView.currentPage = 0
            flipperViewArray = [cvc, nvc]
        } else {
            pvc.configure(for: dateByAdding(dayCount: -1, to: date))
            nvc.configure(for: dateByAdding(dayCount: 1, to: date))
            flipView.currentPage = 1
            flipperViewArray = [pvc, cvc, nvc]
        }
    }
    
    //MARK: - FlipperDataSource Methods
    
    func numberOfPages(_ flipper: DJKFlipperView) -> NSInteger {
        return flipperViewArray?.count ?? 0
    }
    
    func viewForPage(_ page: NSInteger, flipper: DJKFlipperView) -> UIView {
        return flipperViewArray![page].view
    }
    
    func didFlipToNewPage(_ next: Bool) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let maxDate = datePicker?.maximumDate, let dateStr = dateButton?.title(for: .normal), let date = dateFormatter.date(from: dateStr) else {
           return
        }
        let str = dateByAdding(dayCount: next ? 1 : -1, to: date)
        guard let newDate = dateFormatter.date(from: str), newDate <= maxDate else { return }
        self.configure(for: str)
        manageFlipViewControllers()
    }
}
