//
//  TrackingModeMapView.swift
//  TrackUs
//
//  Created by 석기권 on 2024/02/20.
//
// TODO: - 백그라운드 모드에서 위치데이터 추가
// Flow
// 1. 백그라운드진입 감지
// 2. LocationManage의 delegate를 현재뷰로 설정
// 3. 백그라운드에서 위치를 업데이트
// 4. 포그라운드진입 감지
// 5. LocationManage의 delegate를 nil로 설정(업데이트 중지)

import SwiftUI
import MapboxMaps

/**
 라이브트래킹 맵뷰
 */
struct RunningActivityVCHosting: UIViewControllerRepresentable {
    @EnvironmentObject var router: Router
    public var runViewModel: RunActivityViewModel
    
    func makeUIViewController(context: Context) -> UIViewController {
        return RunningActivityVC(
            router: router,
            runViewModel: runViewModel)
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
    
    func makeCoordinator() -> RunningActivityVC {
        return RunningActivityVC(
            router: router,
            runViewModel: runViewModel)
    }
}


final class RunningActivityVC: UIViewController, GestureManagerDelegate {
    private let router: Router
    private let runViewModel: RunActivityViewModel!
    private var mapView: MapView!
    private let locationService = LocationService.shared
    private var locationTrackingCancellation: AnyCancelable?
    private var cancellation = Set<AnyCancelable>()
    private var puckConfiguration = Puck2DConfiguration.makeDefault(showBearing: true)
    
    // UI
    private let buttonWidth = 86.0
    
    private lazy var pauseButton: UIButton = {
        let button = makeCircleButton(systemImageName: "pause.fill")
        button.addTarget(self, action: #selector(pauseButtonTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()
    
    private lazy var playButton: UIButton = {
        let button = makeCircleButton(systemImageName: "play.fill")
        button.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var stopButton: UIButton = {
        let button = makeCircleButton(systemImageName: "stop.fill")
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(stopButtonTapped))
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(stopButtonLongPressed))
        button.addGestureRecognizer(tapGesture)
        button.addGestureRecognizer(longPressGesture)
        return button
    }()
    
    private lazy var countLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        if let descriptor = UIFont.systemFont(ofSize: 128.0, weight: .bold).fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
            label.font = UIFont(descriptor: descriptor, size: 0)
        } else {
            label.font = UIFont.systemFont(ofSize: 128.0, weight: .bold)
        }
        label.textColor = .white
        return label
    }()
    
    private lazy var countTextLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "잠시후 러닝이 시작됩니다!"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 20, weight: .heavy)
        return label
    }()
    
    private lazy var overlayView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.frame = self.view.bounds
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()
    
    private lazy var buttonStackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.distribution = .equalSpacing
        sv.spacing = 16
        sv.isHidden = true
        return sv
    }()
    
    private lazy var roundedVStackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.layer.cornerRadius = 25
        sv.backgroundColor = .white
        sv.axis = .horizontal
        sv.layer.shadowOffset = CGSize(width: -1, height: 1)
        sv.layer.shadowColor = UIColor.black.cgColor
        sv.layer.shadowOpacity = 0.3
        sv.alignment = .center
        sv.isHidden = true
        sv.spacing = 8.0
        sv.axis = .horizontal
        sv.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        sv.isLayoutMarginsRelativeArrangement = true
        return sv
    }()
    
    private lazy var kilometerLabel: UILabel = {
        let label = UILabel()
        label.text = "0.0km"
        label.textColor = .gray1
        if let descriptor = UIFont.systemFont(ofSize: 16.0, weight: .bold).fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
            label.font = UIFont(descriptor: descriptor, size: 0)
        } else {
            label.font = UIFont.systemFont(ofSize: 16.0, weight: .bold)
        }
        return label
    }()
    
    private lazy var circleHStackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.alignment = .center
        sv.distribution = .equalSpacing
        sv.isHidden = true
        return sv
    }()
    
    private lazy var spacerView: UIView = {
        let view = UIView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }()
    
    private lazy var calorieLable: UILabel = {
        let label = makeBigTextLabel(text: "0.0")
        return label
    }()
    
    private lazy var paceLabel: UILabel = {
        let label = makeBigTextLabel(text: "_'__''")
        return label
    }()
    
    private lazy var timeLabel: UILabel = {
        let label = makeBigTextLabel(text: "00:00")
        return label
    }()
    
    init(router: Router, runViewModel: RunActivityViewModel) {
        self.router = router
        self.runViewModel = runViewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
        bind()
        runViewModel.start()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        
        // 백그라운드 진입
        if #available(iOS 13.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(enterBackground), name: UIScene.willDeactivateNotification, object: nil)
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(enterBackground), name: UIApplication.willResignActiveNotification, object: nil)
        }
        
        // 포어그라운드 진입
        if #available(iOS 13.0, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(enterForeground), name: UIScene.willEnterForegroundNotification, object: nil)
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(enterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(true)
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - BackgroundTask 관련
extension RunningActivityVC: CLLocationManagerDelegate {
    // 위치업데이트
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }
        
        self.runViewModel.addPath(withCoordinate: location.asCLLocationCoordinate2D)
    }
    
    @objc func enterBackground() {
        locationService.locationManager.delegate = self
    }
    
    @objc func enterForeground() {
        locationService.locationManager.delegate = nil
    }
}

// MARK: - Setup UI
extension RunningActivityVC {
    /// UI 설정
    private func setupUI() {
        // setup UI
        let distanceToNowLabel = makeTextLabel(text: "현재까지 거리")
        let distanceToNowImage = UIImageView(image: UIImage(named: "distance_icon"))
        
        [distanceToNowImage, distanceToNowLabel, kilometerLabel].forEach { roundedVStackView.addArrangedSubview($0) }
        
        self.roundedVStackView.addArrangedSubview(spacerView)
        self.roundedVStackView.addArrangedSubview(kilometerLabel)
        
        let calorieStackView = makeCircleStackView()
        let paceStackView = makeCircleStackView()
        let timeStackView = makeCircleStackView()
        
        let fireImage = UIImageView(image: UIImage(named: "fire_icon"))
        let paceImage = UIImageView(image: UIImage(named: "pace_icon"))
        let timeImage = UIImageView(image: UIImage(named: "time_img"))
        
        let calorieTextLabel = makeTextLabel(text: "소모 칼로리")
        let paceTextLabel = makeTextLabel(text: "페이스")
        let timeTextLabel = makeTextLabel(text: "경과시간")
        
        [fireImage, calorieTextLabel, calorieLable].forEach { calorieStackView.addArrangedSubview($0) }
        [paceImage, paceTextLabel, paceLabel].forEach { paceStackView.addArrangedSubview($0) }
        [timeImage, timeTextLabel, timeLabel].forEach { timeStackView.addArrangedSubview($0) }
        [calorieStackView, paceStackView, timeStackView].forEach { circleHStackView.addArrangedSubview($0) }
        
        // Add View's
        self.view.addSubview(overlayView)
        self.view.addSubview(countLabel)
        self.view.addSubview(countTextLabel)
        self.view.addSubview(roundedVStackView)
        self.view.addSubview(pauseButton)
        self.view.addSubview(buttonStackView)
        self.view.addSubview(circleHStackView)
        
        [stopButton, playButton].forEach { self.buttonStackView.addArrangedSubview($0) }
        
        NSLayoutConstraint.activate([
            self.countLabel.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.countLabel.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
            self.countTextLabel.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.countTextLabel.topAnchor.constraint(equalTo: self.countLabel.lastBaselineAnchor, constant: 20),
            
            self.stopButton.widthAnchor.constraint(equalToConstant: buttonWidth),
            self.stopButton.heightAnchor.constraint(equalToConstant: buttonWidth),
            self.playButton.widthAnchor.constraint(equalToConstant: buttonWidth),
            self.playButton.heightAnchor.constraint(equalToConstant: buttonWidth),
            self.pauseButton.widthAnchor.constraint(equalToConstant: buttonWidth),
            self.pauseButton.heightAnchor.constraint(equalToConstant: buttonWidth),
            self.pauseButton.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.pauseButton.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            self.buttonStackView.heightAnchor.constraint(equalToConstant: 90),
            self.buttonStackView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            self.buttonStackView.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -40),
            self.buttonStackView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            
            self.roundedVStackView.heightAnchor.constraint(equalToConstant: 53),
            self.roundedVStackView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 10),
            self.roundedVStackView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            self.roundedVStackView.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            
            self.circleHStackView.heightAnchor.constraint(equalToConstant: 100),
            self.circleHStackView.topAnchor.constraint(equalTo: self.roundedVStackView.bottomAnchor, constant: 20),
            self.circleHStackView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            self.circleHStackView.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }
    
    func gestureManager(_ gestureManager: MapboxMaps.GestureManager, didBegin gestureType: MapboxMaps.GestureType) {
        
    }
    
    func gestureManager(_ gestureManager: MapboxMaps.GestureManager, didEnd gestureType: MapboxMaps.GestureType, willAnimate: Bool) {
        
    }
    
    func gestureManager(_ gestureManager: MapboxMaps.GestureManager, didEndAnimatingFor gestureType: MapboxMaps.GestureType) {
        
    }
}

// MARK: - Interaction with combine
extension RunningActivityVC {
    /// 맵뷰 설정 & 초기 카메라 셋팅
    private func setupCamera() {
        /// 초기위치 및 카메라
        guard let location = locationService.currentLocation?.coordinate else { return }
        
        let cameraOptions = CameraOptions(center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude), zoom: 16)
        let options = MapInitOptions(cameraOptions: cameraOptions)
        self.mapView = MapView(frame: view.bounds, mapInitOptions: options)
        self.mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(mapView)
        
        /// 맵뷰 기본설정
        self.mapView.location.options.puckType = .puck2D()
        self.mapView.location.options.puckBearingEnabled = true
        self.mapView.gestures.delegate = self
        self.mapView.mapboxMap.styleURI = .init(rawValue: "mapbox://styles/seokki/clslt5i0700m901r64bli645z")
        self.puckConfiguration.topImage = UIImage(named: "puck_icon")
        self.mapView.location.options.puckType = .puck2D(puckConfiguration)
    }
    
    // 뷰에 갱신될 값들을 바인딩
    private func bind() {
        runViewModel.$count.receive(on: DispatchQueue.main).sink { [weak self] count in
            self?.countLabel.text = "\(count)"
            if count == 0 {
                self?.updatedOnStart()
            }
        }.store(in: &cancellation)
        
        // 운동시간
        runViewModel.$seconds.receive(on: DispatchQueue.main).sink { [weak self] seconds in
            guard let self = self else { return }
            self.timeLabel.text = seconds.asString(style: .positional)
        }.store(in: &cancellation)
        
        // 이동거리
        runViewModel.$distance.receive(on: DispatchQueue.main).sink { [weak self] distance in
            guard let self = self else { return }
            
            self.kilometerLabel.text = "\(distance.asString(unit: .kilometer)) / \(runViewModel.target.asString(unit: .kilometer))"
        }.store(in: &cancellation)
        
        // 칼로리
        runViewModel.$calorie.receive(on: DispatchQueue.main).sink { [weak self] calorie in
            guard let self = self else { return }
            self.calorieLable.text = String(format: "%.1f", calorie)
        }.store(in: &cancellation)
        
        // 페이스
        runViewModel.$pace.receive(on: DispatchQueue.main).sink { [weak self] pace in
            guard let self = self else { return }
            self.paceLabel.text = pace.asString(unit: .pace)
            
        }.store(in: &cancellation)
    }
    
    // 카운트다운 종료시
    private func updatedOnStart() {
        self.roundedVStackView.isHidden = false
        self.circleHStackView.isHidden = false
        self.overlayView.isHidden = true
        self.countLabel.isHidden = true
        self.countTextLabel.isHidden = true
        self.pauseButton.isHidden = false
        self.runViewModel.play()
        self.startTracking()
    }
    
    // 일시중지 됬을때
    private func updatedOnPause() {
        self.buttonStackView.isHidden = false
        self.overlayView.isHidden = false
        self.pauseButton.isHidden = true
        self.runViewModel.stop()
        self.stopTracking()
    }
    
    // 기록중일떄
    private func updatedOnPlay() {
        self.buttonStackView.isHidden = true
        self.overlayView.isHidden = true
        self.pauseButton.isHidden = false
        self.runViewModel.play()
        self.startTracking()
    }
    
    // 위치받아오기 시작
    private func startTracking() {
        // 맵뷰에서 컴바인 형식으로 새로운 위치를 받아옴(사용자가 이동할떄마다 값을 방출)
        locationTrackingCancellation = mapView.location.onLocationChange.observe { [weak mapView] newLocation in
            // 새로받아온 위치
            guard let location = newLocation.last, let mapView else { return }
            
            self.runViewModel.addPath(withCoordinate: location.coordinate)
            
            mapView.camera.ease(
                to: CameraOptions(center: location.coordinate, zoom: 15),
                duration: 1.3)
        }
    }
    
    // 위치받아오기 종료
    private func stopTracking() {
        locationTrackingCancellation?.cancel()
    }
}

// MARK: - 버튼동작 관련
extension RunningActivityVC {
    // 일시중지 버튼이 눌렸을때
    @objc func pauseButtonTapped() {
        updatedOnPause()
    }
    
    // 플레이 버튼이 눌렸을때
    @objc func playButtonTapped() {
        updatedOnPlay()
    }
    
    // 중지 버튼이 눌렸을때
    @objc func stopButtonTapped() {
        self.showToast(message: "종료 버튼을 2초간 탭하면 운동이 종료됩니다.")
    }
    
    // 중지버튼 롱프레스
    @objc func stopButtonLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            self.stopTracking()
            self.runViewModel.stop()
            self.router.push(.runningResult(runViewModel))
        }
    }
}

// MARK: - UI Generator
extension RunningActivityVC {
    
    private func makeCircleStackView() -> UIStackView {
        let circleDiameter: CGFloat = 98.0
        let circleView = UIStackView()
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = .white
        circleView.layer.cornerRadius = circleDiameter / 2.0
        circleView.clipsToBounds = true
        circleView.distribution = .equalSpacing
        circleView.alignment = .center
        circleView.axis = .vertical
        circleView.layoutMargins = UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)
        circleView.isLayoutMarginsRelativeArrangement = true
        circleView.widthAnchor.constraint(equalToConstant: circleDiameter).isActive = true
        circleView.heightAnchor.constraint(equalToConstant: circleDiameter).isActive = true
        return circleView
    }
    
    private func makeCircleButton(systemImageName: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        let pauseButtonImage = UIImage(systemName: systemImageName)?.resizeWithWidth(width: 40.0)?.withTintColor(.gray1, renderingMode: .alwaysOriginal)
        button.setImage(pauseButtonImage, for: .normal)
        button.backgroundColor = UIColor(white: 0.97, alpha: 1)
        button.layer.cornerRadius = buttonWidth / 2
        button.layer.shadowOffset = CGSize(width: -1, height: 1)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        return button
    }
    
    private func makeTextLabel(text: String?) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .gray1
        return label
    }
    
    private func makeBigTextLabel(text: String?) -> UILabel {
        let label = UILabel()
        label.textColor = .gray1
        label.text = text
        if let descriptor = UIFont.systemFont(ofSize: 20.0, weight: .bold).fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
            label.font = UIFont(descriptor: descriptor, size: 0)
            
        } else {
            label.font = UIFont.systemFont(ofSize: 20.0, weight: .bold)
        }
        return label
    }
    
    func showToast(message : String, font: UIFont = UIFont.systemFont(ofSize: 14.0)) {
        let toastLabel = UILabel(frame: CGRect(x: self.view.frame.size.width/2 - 135, y: self.view.frame.size.height-230, width: 270, height: 45))
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        toastLabel.textColor = UIColor.white
        toastLabel.font = font
        toastLabel.textAlignment = .center;
        toastLabel.text = message
        toastLabel.alpha = 1.0
        toastLabel.layer.cornerRadius = 10;
        toastLabel.clipsToBounds  =  true
        self.view.addSubview(toastLabel)
        UIView.animate(withDuration: 4.0, delay: 0.1, options: .curveEaseOut, animations: {
            toastLabel.alpha = 0.0
        }, completion: {(isCompleted) in
            toastLabel.removeFromSuperview()
        })
    }
}