function [rectifiedPoints1, rectifiedPoints2] = rectifyStereoPoints(points1, points2, K1, K2, D1, D2, R, T)
    % 计算立体校正变换
    [R1, R2, P1, P2, Q] = stereoRectify(K1, D1, K2, D2, size(frame1), R, T);
    
    % 计算校正映射
    [map1x, map1y] = initUndistortRectifyMap(K1, D1, R1, P1, size(frame1));
    [map2x, map2y] = initUndistortRectifyMap(K2, D2, R2, P2, size(frame2));
    
    % 对特征点进行校正
    rectifiedPoints1 = undistortPoints(points1, K1, D1, R1, P1);
    rectifiedPoints2 = undistortPoints(points2, K2, D2, R2, P2);
    
    % 验证校正结果 - 极线约束
    % 校正后的点对应行应该基本一致
    yDiff = abs(rectifiedPoints1(:,2) - rectifiedPoints2(:,2));
    validIdx = yDiff < 1.0;  % 1像素的容差
    
    rectifiedPoints1 = rectifiedPoints1(validIdx,:);
    rectifiedPoints2 = rectifiedPoints2(validIdx,:);
end